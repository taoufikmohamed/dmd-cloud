
from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
import httpx
import os
import logging
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# Configuration - all configurable via environment variables
AI_SERVICE_URL = os.getenv("AI_SERVICE_URL", "http://ai-service:8000")
AI_SERVICE_TIMEOUT_SECONDS = float(os.getenv("AI_SERVICE_TIMEOUT_SECONDS", "30"))
WEBHOOK_RESPONSE_TIMEOUT = float(os.getenv("WEBHOOK_RESPONSE_TIMEOUT", "5"))  # Must be < 30s

async def call_ai_async(payload: dict, retry_count: int = 0, max_retries: int = 3):
    """
    Call AI service asynchronously with retries and timeout handling.
    This runs in the background and does NOT block the webhook response.
    """
    try:
        logger.info(f"Processing webhook payload (attempt {retry_count + 1}/{max_retries + 1})")
        
        async with httpx.AsyncClient(timeout=AI_SERVICE_TIMEOUT_SECONDS) as client:
            response = await client.post(
                AI_SERVICE_URL,
                json=payload,
                timeout=AI_SERVICE_TIMEOUT_SECONDS
            )
            response.raise_for_status()
            logger.info(f"Successfully sent payload to AI service: {response.status_code}")
            
    except httpx.TimeoutException as e:
        logger.error(f"Timeout calling AI service: {e}")
        if retry_count < max_retries:
            wait_time = 2 ** retry_count  # Exponential backoff: 1s, 2s, 4s
            logger.info(f"Retrying in {wait_time} seconds...")
            time.sleep(wait_time)
            await call_ai_async(payload, retry_count + 1, max_retries)
        else:
            logger.error("Max retries exceeded for AI service call")
            
    except Exception as e:
        logger.error(f"Error calling AI service: {type(e).__name__}: {e}")
        if retry_count < max_retries:
            wait_time = 2 ** retry_count
            logger.info(f"Retrying in {wait_time} seconds...")
            time.sleep(wait_time)
            await call_ai_async(payload, retry_count + 1, max_retries)

@app.post("/webhook/github")
async def github_webhook(request: Request, background_tasks: BackgroundTasks):
    """
    GitHub webhook endpoint. Returns immediately, processes asynchronously.
    GitHub gives us 30 seconds max - we respond in <<1 second.
    """
    try:
        payload = await request.json()
        
        # Log webhook receipt
        repo = payload.get("repository", {}).get("full_name", "unknown")
        logger.info(f"Received webhook for repository: {repo}")
        
        # Add background task - returns immediately without waiting
        background_tasks.add_task(call_ai_async, payload)
        
        # IMMEDIATE response - returns instantly to GitHub
        return {
            "status": "received",
            "message": "Webhook received and queued for processing"
        }
        
    except Exception as e:
        logger.error(f"Error processing webhook: {e}")
        # Still return 202 so GitHub doesn't retry
        return {
            "status": "received",
            "message": "Webhook received (processing may have failed)"
        }

@app.get("/health")
async def health_check():
    """Health check endpoint for Kubernetes liveness/readiness probes"""
    try:
        async with httpx.AsyncClient(timeout=2) as client:
            response = await client.get(f"{AI_SERVICE_URL}/health", timeout=2)
            ai_service_healthy = response.status_code == 200
    except Exception as e:
        logger.warning(f"AI service health check failed: {e}")
        ai_service_healthy = False
    
    return {
        "status": "healthy",
        "ai_service": "healthy" if ai_service_healthy else "unhealthy"
    }

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "webhook-service",
        "github_webhook": "/webhook/github",
        "health": "/health"
    }

