
from fastapi import FastAPI, Request, HTTPException
import httpx
import os

app = FastAPI()
AI_SERVICE_URL = os.getenv("AI_SERVICE_URL", "http://ai-service:8000")
AI_SERVICE_TIMEOUT_SECONDS = float(os.getenv("AI_SERVICE_TIMEOUT_SECONDS", "75"))

@app.post("/webhook/github")
async def github_webhook(request: Request):
    payload = await request.json()
    diff = "Sample diff for testing"

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(AI_SERVICE_TIMEOUT_SECONDS)) as client:
            response = await client.post(
                f"{AI_SERVICE_URL}/generate-pipeline",
                json={"diff": diff}
            )
            response.raise_for_status()
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="AI service request timed out")
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=502, detail=f"AI service returned {exc.response.status_code}")
    except httpx.HTTPError:
        raise HTTPException(status_code=502, detail="AI service is unavailable")

    return {"ai_response": response.json()}
