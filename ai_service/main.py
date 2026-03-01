
from fastapi import FastAPI, HTTPException
import os
import requests

app = FastAPI()
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY")
DEEPSEEK_TIMEOUT_SECONDS = float(os.getenv("DEEPSEEK_TIMEOUT_SECONDS", "60"))

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/generate-pipeline")
def generate_pipeline(data: dict):
    if not DEEPSEEK_API_KEY:
        raise HTTPException(status_code=500, detail="DEEPSEEK_API_KEY is not configured")

    prompt = f"""
    Analyze this git diff and generate a GitHub Actions YAML pipeline:

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

    return response.json()
