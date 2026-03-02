
from fastapi import FastAPI, Request, HTTPException
import httpx
import os
import threading
import requests

app = FastAPI()
AI_SERVICE_URL = os.getenv("AI_SERVICE_URL", "http://ai-service:8000")
AI_SERVICE_TIMEOUT_SECONDS = float(os.getenv("AI_SERVICE_TIMEOUT_SECONDS", "75"))

def call_ai(payload):
    requests.post(AI_SERVICE_URL, json=payload)

@app.post("/webhook/github")
def github_webhook(payload: dict):
    threading.Thread(target=call_ai, args=(payload,)).start()
    return {"status": "received"}

