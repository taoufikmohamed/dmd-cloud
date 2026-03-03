
from fastapi import FastAPI, HTTPException
import os
import re
import requests

app = FastAPI()
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY")
DEEPSEEK_TIMEOUT_SECONDS = float(os.getenv("DEEPSEEK_TIMEOUT_SECONDS", "60"))


def sanitize_pipeline_yaml(content: str) -> str:
    text = (content or "").strip()
    text = re.sub(r"^```(?:ya?ml)?\\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\\s*```$", "", text)

    lines = text.splitlines()
    yaml_start_patterns = (
        "name:",
        "on:",
        "jobs:",
        "permissions:",
        "env:",
        "defaults:",
        "concurrency:",
        "run-name:",
    )

    start_index = None
    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if any(stripped.startswith(pattern) for pattern in yaml_start_patterns):
            start_index = index
            break

    if start_index is None:
        return text

    yaml_lines = lines[start_index:]
    return "\n".join(yaml_lines).strip()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/generate-pipeline")
def generate_pipeline(data: dict):
    if not DEEPSEEK_API_KEY:
        raise HTTPException(status_code=500, detail="DEEPSEEK_API_KEY is not configured")

    prompt = f"""
You are a CI/CD pipeline generator.

Task:
- Analyze the git diff and produce a GitHub Actions workflow.

Output rules (strict):
- Return ONLY raw YAML.
- Do NOT include Markdown fences.
- Do NOT include explanations, notes, or bullet points.
- Do NOT include any text before or after YAML.
- The YAML must be directly saveable as .github/workflows/ci-cd.yml.

Git diff:

    {data.get("diff")}
    """

    try:
        response = requests.post(
            "https://api.deepseek.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {DEEPSEEK_API_KEY}"},
            json={
                "model": "deepseek-coder",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.2
            },
            timeout=DEEPSEEK_TIMEOUT_SECONDS
        )
        response.raise_for_status()
    except requests.Timeout:
        raise HTTPException(status_code=504, detail="DeepSeek API request timed out")
    except requests.ConnectionError as exc:
        if "Read timed out" in str(exc):
            raise HTTPException(status_code=504, detail="DeepSeek API request timed out")
        raise HTTPException(status_code=502, detail="DeepSeek API is unavailable")
    except requests.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"DeepSeek API returned {exc.response.status_code}")
    except requests.RequestException:
        raise HTTPException(status_code=502, detail="DeepSeek API is unavailable")

    payload = response.json()
    try:
        content = payload["choices"][0]["message"].get("content", "")
        payload["choices"][0]["message"]["content"] = sanitize_pipeline_yaml(content)
    except (KeyError, IndexError, TypeError):
        pass

    return payload
