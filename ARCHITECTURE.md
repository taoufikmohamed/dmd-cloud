# DMD Cloud - Detailed Architecture

This document provides in-depth technical architecture, UML diagrams, and implementation details.

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            EXTERNAL SYSTEMS                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────┐              ┌──────────────────┐                     │
│  │   GitHub     │              │   DeepSeek API   │                     │
│  │  Repository  │              │  LLM Inference   │                     │
│  └──────┬───────┘              └────────────┬─────┘                     │
│         │ Push Event                        │                            │
│         │ (Webhook)                         │ HTTPS /v1/chat/           │
│         │                                   │ completions               │
│         └───────────────┬────────────────────┬──────┐                   │
└─────────────────────────┼──────────────────────────────────────────────┘
                          │                        │
                          ↓                        │
              ┌───────────────────────┐            │
              │     ngrok Tunnel      │            │
              │  (Public URL)         │            │
              └───────────┬───────────┘            │
                          │                        │
                          ↓                        │
    ┌─────────────────────────────────────────────┴─────────────────────┐
    │                  KUBERNETES / MINIKUBE CLUSTER                    │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                  │
    │  ┌──────────────────────────────────────────────────────────┐  │
    │  │            WEBHOOK SERVICE (Port 8001)                  │  │
    │  │                                                          │  │
    │  │  Pod 1: webhook-service-79467b9bd5-h5kcv               │  │
    │  │  ┌──────────────────────────────────┐                  │  │
    │  │  │  FastAPI Application on 0.0.0.0:8001              │  │
    │  │  │  ├─ POST /webhook/github                          │  │
    │  │  │  ├─ GET /health                                    │  │
    │  │  │  └─ GET /                                          │  │
    │  │  └─┬────────────────────────────────┘                  │  │
    │  │    │                                                    │  │
    │  │    ├─ Receives GitHub webhook                          │  │
    │  │    ├─ Extracts: {diff, repository, commit_message}   │  │
    │  │    ├─ Responds 200 OK immediately (< 100ms)          │  │
    │  │    ├─ Queues background async task (call_ai_async) │  │
    │  │    └─ Polls: for_status in retry_loop              │  │
    │  │       ├─ retry_count ≤ 3                             │  │
    │  │       ├─ wait_time = 2^retry_count (1s,2s,4s)       │  │
    │  │       ├─ timeout = 90 seconds                        │  │
    │  │       └─ on success: save_generated_pipeline()      │  │
    │  │                                                        │  │
    │  │  Pod 2: webhook-service-79467b9bd5-xs46s (identical)│  │
    │  │                                                        │  │
    │  │  Service: webhook-service (NodePort:8001)           │  │
    │  └────────┬────────────────────────────────────────────┘  │
    │           │                                                │
    │           │ HTTP POST to http://ai-service:8000           │
    │           │ {diff, repository, commit_message}            │
    │           ↓                                                │
    │  ┌──────────────────────────────────────────────────────┐  │
    │  │              AI SERVICE (Port 8000)                  │  │
    │  │                                                       │  │
    │  │  Pod: ai-service-7db99c664f-57sht                   │  │
    │  │  ┌─────────────────────────────────────────────┐    │  │
    │  │  │  FastAPI Application on 0.0.0.0:8000       │    │  │
    │  │  │  ├─ POST /generate-pipeline                │    │  │
    │  │  │  ├─ GET /health                             │    │  │
    │  │  │  └─ GET /                                   │    │  │
    │  │  └─┬───────────────────────────────────────────┘    │  │
    │  │    │                                                  │  │
    │  │    ├─ Receive AI request with diff                   │  │
    │  │    ├─ Build prompt: "Generate YAML-only pipeline"   │  │
    │  │    ├─ Call DeepSeek /v1/chat/completions (HTTPS)  │  │
    │  │    │  ├─ Authorization: Bearer {DEEPSEEK_API_KEY}   │  │
    │  │    │  ├─ Model: deepseek-chat                        │  │
    │  │    │  ├─ Temperature: 0.2 (deterministic)            │  │
    │  │    │  └─ Timeout: 60 seconds                         │  │
    │  │    ├─ Receive YAML content from DeepSeek            │  │
    │  │    ├─ Sanitize: remove_markdown_fences()            │  │
    │  │    ├─ Sanitize: remove_leading_prose()              │  │
    │  │    ├─ Return pure YAML in response                  │  │
    │  │    └─ On error: catch → HTTP 502/504 with details  │  │
    │  │                                                       │  │
    │  │  Service: ai-service (ClusterIP:8000, internal-only)│  │
    │  └─────────────────────────────────────────────────────┘  │
    │                                                            │
    │  ┌──────────────────────────────────────────────────────┐  │
    │  │             KUBERNETES SECRETS                       │  │
    │  │  Secret: ai-service-secrets                         │  │
    │  │  ├─ DEEPSEEK_API_KEY: "sk-..."                     │  │
    │  │  └─ Mounted to ai-service pod                       │  │
    │  └──────────────────────────────────────────────────────┘  │
    │                                                            │
    │  ┌──────────────────────────────────────────────────────┐  │
    │  │         K8S CONTROL PLANE (Health Checks)           │  │
    │  │                                                       │  │
    │  │  Liveness Probe: GET /health every 30s             │  │
    │  │  ├─ Timeout: 5s                                      │  │
    │  │  ├─ Failure threshold: 3                             │  │
    │  │  └─ Action: Kill pod if 3 consecutive failures     │  │
    │  │                                                       │  │
    │  │  Readiness Probe: GET /health every 10s            │  │
    │  │  ├─ Timeout: 5s                                      │  │
    │  │  ├─ Failure threshold: 2                             │  │
    │  │  └─ Action: Remove from load balancer if fails      │  │
    │  └──────────────────────────────────────────────────────┘  │
    │                                                            │
    └────────────────────────────────────────────────────────────┘
```

## UML Class Diagram

```
┌─────────────────────────────────────────────────────────────┐
│              webhook_service.main:FastAPI                    │
├─────────────────────────────────────────────────────────────┤
│  ATTRIBUTES:                                                 │
│  - app: FastAPI                                              │
│  - logger: logging.Logger                                    │
│  - AI_SERVICE_URL: str = "http://ai-service:8000"           │
│  - AI_SERVICE_TIMEOUT_SECONDS: float = 90.0                │
│  - AUTO_SAVE_PIPELINE: bool = True                          │
│  - PIPELINE_OUTPUT_PATH: str = ".github/workflows/ci-cd.yml"│
├─────────────────────────────────────────────────────────────┤
│  METHODS:                                                    │
│  + github_webhook(request, background_tasks)                │
│    → POST /webhook/github                                   │
│    → Returns: {"status":"received", "message":"..."}       │
│                                                              │
│  + call_ai_async(payload, retry_count, max_retries)        │
│    → Background task                                        │
│    → Extracts diff, calls AI service                        │
│    → Implements retry logic with exponential backoff        │
│    → Saves YAML on success                                  │
│                                                              │
│  + save_generated_pipeline(pipeline_content)               │
│    → Writes YAML to file                                   │
│    → Creates .github/workflows/ directory                  │
│                                                              │
│  + health_check()                                           │
│    → GET /health                                            │
│    → Returns: {"status":"healthy", ...}                    │
│                                                              │
│  + root()                                                   │
│    → GET /                                                  │
│    → Returns: {"service":"webhook-service", ...}          │
└─────────────────────────────────────────────────────────────┘
          │
          │ calls
          ↓
┌─────────────────────────────────────────────────────────────┐
│               ai_service.main:FastAPI                        │
├─────────────────────────────────────────────────────────────┤
│  ATTRIBUTES:                                                 │
│  - app: FastAPI                                              │
│  - DEEPSEEK_API_KEY: str (from K8s Secret)                 │
│  - DEEPSEEK_TIMEOUT_SECONDS: float = 60.0                  │
├─────────────────────────────────────────────────────────────┤
│  METHODS:                                                    │
│  + generate_pipeline(data: dict)                            │
│    → POST /generate-pipeline                                │
│    Input: {diff, repository, commit_message}               │
│    → Builds prompt with strict YAML-only instructions      │
│    → Calls requests.post() to DeepSeek API                 │
│    → Sanitizes response via sanitize_pipeline_yaml()       │
│    → Returns: DeepSeek response with clean YAML            │
│                                                              │
│  + sanitize_pipeline_yaml(content)                          │
│    → Removes markdown fences (```)                          │
│    → Removes leading prose                                  │
│    → Returns strict YAML only                              │
│                                                              │
│  + health()                                                 │
│    → GET /health                                            │
│    → Returns: {"status":"ok"}                              │
└─────────────────────────────────────────────────────────────┘
          │
          │ calls
          ↓
┌─────────────────────────────────────────────────────────────┐
│              DeepSeek API (External)                         │
├─────────────────────────────────────────────────────────────┤
│  ENDPOINT: https://api.deepseek.com/v1/chat/completions    │
│                                                              │
│  REQUEST: {                                                 │
│    "model": "deepseek-chat",                                │
│    "messages": [{                                           │
│      "role": "user",                                        │
│      "content": "[prompt with code diff]"                  │
│    }],                                                      │
│    "temperature": 0.2                                       │
│  }                                                          │
│                                                              │
│  RESPONSE: {                                                │
│    "id": "chatcmpl-xxx",                                    │
│    "choices": [{                                            │
│      "message": {                                           │
│        "content": "[generated GitHub Actions YAML]"        │
│      }                                                      │
│    }]                                                       │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘
```

## Sequence Diagram

```
┌──────┬────────────┬──────────┬────────────┐
│GitHub│  ngrok     │  Webhook │    AI      │
│ Repo │  Tunnel    │ Service  │  Service   │
└──┬───┴────┬───────┴────┬─────┴────┬───────┘
   │        │            │          │
   │        │            │          │
   ├─PUSH──→│ Webhooks   │          │
   │ Code   │ Event      │          │
   │        │            │          │
   │        ├─POST /webhook/github──→
   │        │  {diff,repo,...}      │
   │        │            │          │
   │        │            ├──┐       │
   │        │            │  │ Enqueue
   │        │            │  │ Background
   │        │   200 OK    │  │ Task
   │        │←───────────┤──┤
   │        │            │  │
   │        │            │←─┘
   │        │            │
   │        │            │[After ~100ms, background task starts]
   │        │            │
   │        │            ├─POST /generate-pipeline─→
   │        │            │ {diff, repo, msg}       │
   │        │            │                         │
   │        │            │    ├─HTTPS──────────────→ DeepSeek
   │        │            │    │ /v1/chat/completions
   │        │            │    │
   │        │            │    │ [20-30 seconds of LLM inference]
   │        │            │    │
   │        │            │    ←─YAML Response──────┤
   │        │            │    │
   │        │            │    ├─Sanitize (remove prose)
   │        │            │    │
   │        │            │←─YAML Response─────────┤
   │        │            │ (pure YAML)             │
   │        │            │
   │        │            ├─Save to file
   │        │            │ .github/workflows/ci-cd.yml
   │        │            │
   │        │            └─Log: "Pipeline saved"
   │        │
```

## Data Model

### GitHub Webhook Payload (Input)

```json
{
  "action": "opened",
  "number": 123,
  "pull_request": {
    "id": 12345,
    "title": "Add feature X"
  },
  "repository": {
    "id": 67890,
    "name": "repo-name",
    "full_name": "org/repo",
    "html_url": "https://github.com/org/repo"
  },
  "head_commit": {
    "id": "abc123def456",
    "message": "Add authentication module",
    "url": "https://github.com/org/repo/commit/abc123"
  },
  "diff": "diff --git a/src/auth.py b/src/auth.py\n...",
  "before": "old-commit-hash",
  "after": "new-commit-hash"
}
```

### Webhook Service Internal Request (to AI Service)

```json
{
  "diff": "diff --git a/src/auth.py b/src/auth.py\n+import os\n+class Auth:",
  "repository": "org/repo",
  "commit_message": "Add authentication module"
}
```

### AI Service Response (from DeepSeek)

```json
{
  "id": "chatcmpl-8v3...9z",
  "object": "chat.completion",
  "created": 1772520401,
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "name: CI/CD Pipeline\n\non:\n  push:\n    branches: [main]\n\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v3\n      - uses: actions/setup-python@v4\n      - run: python -m pytest"
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 120,
    "completion_tokens": 127,
    "total_tokens": 247
  }
}
```

### Generated GitHub Actions Pipeline (Output)

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: actions/setup-python@v4
      with:
        python-version: '3.9'
    - run: pip install -r requirements.txt
    - run: python -m pytest
    
  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - run: echo "Deploying..."
```

## Kubernetes Resource Definitions

### Webhook Service Deployment

**Resource Type:** Deployment  
**Replicas:** 2 (high availability)  
**Image:** webhook-service:latest  
**Port:** 8001  

**Resource Limits:**
- CPU Request: 250m / Limit: 500m
- Memory Request: 64Mi / Limit: 256Mi

**Probes:**
- Liveness: GET /health every 30s (timeout 5s, failure threshold 3)
- Readiness: GET /health every 10s (timeout 5s, failure threshold 2)

**Environment Variables:**
- AI_SERVICE_URL = "http://ai-service:8000"
- AI_SERVICE_TIMEOUT_SECONDS = "90"
- AUTO_SAVE_PIPELINE = "true"
- PIPELINE_OUTPUT_PATH = ".github/workflows/ci-cd.yml"

### AI Service Deployment

**Resource Type:** Deployment  
**Replicas:** 1  
**Image:** ai-service:latest  
**Port:** 8000  

**Resource Limits:**
- CPU Request: 250m / Limit: 500m
- Memory Request: 256Mi / Limit: 512Mi

**Probes:**
- Liveness: GET /health every 30s
- Readiness: GET /health every 10s

**Secret Mount:**
- DEEPSEEK_API_KEY from ai-service-secrets

**Environment Variables:**
- DEEPSEEK_TIMEOUT_SECONDS = "60"

## Processing Flow (Detailed)

```
1. WEBHOOK RECEPTION
   ├─ Time: T=0ms
   ├─ Event: GitHub sends POST to /webhook/github
   ├─ Payload: {repository, diff, commit_message}
   └─ State: Incoming HTTP request

2. REQUEST VALIDATION & PARSING
   ├─ Time: T=5ms
   ├─ Action: Parse JSON payload
   ├─ Extract: repo_name, commit_msg, diff
   └─ Check: Diff not empty

3. IMMEDIATE RESPONSE TO GITHUB
   ├─ Time: T=50ms
   ├─ Action: Respond 200 OK
   ├─ Body: {"status":"received", "message":"..."}
   ├─ Purpose: Achnowledge webhook within GitHub's timeout
   └─ GitHub marks webhook delivery as success

4. QUEUE BACKGROUND TASK
   ├─ Time: T=75ms
   ├─ Action: Add async task to queue
   ├─ Task: call_ai_async(payload)
   └─ Control: Returns to HTTP handler immediately

5. BACKGROUND PROCESSING (async)
   ├─ Time: T=100-150ms (task starts)
   ├─ Action: Extract diff from payload
   ├─ Log: "Extracted diff from repository"
   └─ State: Ready to call AI service

6. CALL AI SERVICE (Attempt 1)
   ├─ Time: T=200ms
   ├─ Method: POST http://ai-service:8000/generate-pipeline
   ├─ Payload: {diff, repository, commit_message}
   ├─ Timeout: 90 seconds
   └─ State: Waiting for AI response

7. AI SERVICE PROCESSING
   ├─ Time: T=300ms (AI pod receives request)
   ├─ Action: Parse request, build prompt
   ├─ Prompt: "Generate YAML-only pipeline for this diff..."
   ├─ State: Ready to call DeepSeek

8. DEEPSEEK API CALL
   ├─ Time: T=400ms (API call starts)
   ├─ Method: HTTPS POST to https://api.deepseek.com/v1/chat/completions
   ├─ Headers: Authorization: Bearer {DEEPSEEK_API_KEY}
   ├─ Body: {model, messages, temperature=0.2}
   ├─ Timeout: 60 seconds
   └─ State: LLM inference in progress

9. LLM INFERENCE
   ├─ Time: T=400ms - T=25000ms (15-25 seconds)
   ├─ Action: DeepSeek processes code diff
   ├─ Process: Token-by-token generation
   ├─ Output: GitHub Actions YAML pipeline
   └─ State: Generating completion

10. DEEPSEEK RESPONSE
    ├─ Time: T=25000ms (response arrives)
    ├─ Content: YAML with potential markdown artifacts
    ├─ Status: 200 OK
    └─ State: AI service processes response

11. RESPONSE SANITIZATION
    ├─ Time: T=25100ms
    ├─ Action: Remove markdown fences (```)
    ├─ Action: Remove leading prose/explanations
    ├─ Result: Pure YAML only
    └─ State: Ready to return to webhook service

12. RETURN TO WEBHOOK SERVICE
    ├─ Time: T=25200ms
    ├─ Content: Clean YAML response
    ├─ HTTP Status: 200 OK
    └─ State: Webhook service receives pipeline

13. FILE SAVE
    ├─ Time: T=25300ms
    ├─ Action: Create .github/workflows/ directory
    ├─ Action: Write YAML to .github/workflows/ci-cd.yml
    ├─ Action: Close file handle
    └─ State: File persisted

14. LOGGING & COMPLETION
    ├─ Time: T=25500ms
    ├─ Log: "Generated CI/CD Pipeline:"
    ├─ Log: [YAML content]
    ├─ Log: "Pipeline saved to: /app/.github/workflows/ci-cd.yml"
    └─ State: Task complete

RETRY FLOW (if step 8 times out):
├─ If retry_count < 3:
│  ├─ Log: "Error calling AI service"
│  ├─ Calculate: wait_time = 2^retry_count
│  ├─ action: Sleep wait_time seconds (1s, 2s, 4s)
│  └─ Retry: Jump to step 6 with retry_count+1
└─ If retry_count >= 3:
   ├─ Log: "Max retries exceeded"
   └─ State: Task abandoned
```

## Error Handling

### Webhook Service Errors

```
┌─────────────────────────────────────────┐
│ Error: Payload parsing fails            │
├─────────────────────────────────────────┤
│ Status: 200 OK (always)                 │
│ Response: {"status":"received",...}     │
│ Log: ERROR - Error processing webhook   │
│ Action: Continue, don't retry           │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Error: AI service unreachable           │
├─────────────────────────────────────────┤
│ Status: (not returned, background task) │
│ Log: ERROR - Error calling AI service   │
│ Action: Retry 3 times with backoff      │
│ Wait: 1s, 2s, 4s between retries        │
│ Final: Log max retries exceeded         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Error: AI service timeout               │
├─────────────────────────────────────────┤
│ Timeout: 90 seconds                     │
│ Log: ERROR - Timeout calling AI service │
│ Action: Retry with exponential backoff  │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Error: File write fails                 │
├─────────────────────────────────────────┤
│ Cause: Permission denied / No space     │
│ Log: ERROR - Failed to save generated   │
│ Action: Log error but don't crash       │
│ Status: Pipeline still generated, not   │
│         persisted to disk                │
└─────────────────────────────────────────┘
```

### AI Service Errors

```
┌─────────────────────────────────────────┐
│ Error: Missing API key                  │
├─────────────────────────────────────────┤
│ Status: 500 Internal Server Error       │
│ Response: detail: "DEEPSEEK_API_KEY..." │
│ Log: Error in console & DeepSeek logs   │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Error: Invalid API key                  │
├─────────────────────────────────────────┤
│ Status: 502 Bad Gateway                 │
│ Response: detail: "DeepSeek API returned│
│          401"                             │
│ Log: HTTPError from requests library    │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Error: DeepSeek API timeout             │
├─────────────────────────────────────────┤
│ Timeout: 60 seconds                     │
│ Status: 504 Gateway Timeout             │
│ Response: detail: "DeepSeek API request │
│          timed out"                      │
│ Log: requests.Timeout exception         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Error: DeepSeek unavailable             │
├─────────────────────────────────────────┤
│ Status: 502 Bad Gateway                 │
│ Response: detail: "DeepSeek API is      │
│          unavailable"                    │
│ Log: ConnectionError from requests      │
└─────────────────────────────────────────┘
```

## Performance Analysis

### Latency Breakdown

```
Phase                          Duration    Percentage
────────────────────────────────────────────────────
1. Webhook HTTP handshake      ~50ms        0.3%
2. Request parsing             ~5ms         0.0%
3. Background task queue       ~25ms        0.2%
4. Response to GitHub          ~100ms       0.6%
   ──────────────────────────────────────────────
   Webhook RTT subtotal        ~100ms       0.6%

5. AI service call setup       ~100ms       0.6%
6. DeepSeek API call start     ~150ms       0.9%
7. LLM inference               15-25s       90-99%
8. Response transmission       ~500ms       3.0%
9. YAML sanitization           ~100ms       0.6%
10. File I/O write             ~200ms       1.2%
11. Logging operations         ~50ms        0.3%
    ──────────────────────────────────────────────
    AI processing subtotal     15-30s       99.4%

    ════════════════════════════════════════════════
    TOTAL END-TO-END            15-30s       100%
    ════════════════════════════════════════════════
```

### Throughput Capacity

```
Single Webhook Service Pod:
├─ HTTP connections: ~100 concurrent
├─ Requests/minute: ~10 (due to AI wait)
├─ Requests/hour: ~600
└─ Daily capacity: ~14,400

With 2 Webhook Pods:
├─ Total concurrent: ~200
├─ Requests/minute: ~20
├─ Requests/hour: ~1,200
└─ Daily capacity: ~28,800

With 5 Webhook Pods + 3 AI Pods:
├─ Total concurrent: ~500
├─ Requests/minute: ~50
├─ Requests/hour: ~3,000
└─ Daily capacity: ~72,000

Bottleneck: DeepSeek API rate limits
Recommendation: Scale pods based on quota
```

## Security Model

```
┌──────────────────────────────────────────┐
│    External (Internet-facing)            │
├──────────────────────────────────────────┤
│ GitHub Repository                        │
│  └─ Webhook POST (HTTPS)                │
│     └─ ngrok Tunnel (HTTPS)             │
│        └─ Minikube NodePort:8001 (HTTP) │
└─────────────┬──────────────────────────────┘
              │
┌─────────────▼──────────────────────────────┐
│    Kubernetes Cluster (Protected)          │
├────────────────────────────────────────────┤
│ webhook-service (NodePort 8001)           │
│  └─ Receives webhooks (no auth)           │
│     └─ Calls ai-service (ClusterIP)      │
│        └─ No external access             │
│                                           │
│ ai-service (ClusterIP 8000)               │
│  └─ Internal only                         │
│     └─ Calls DeepSeek API (HTTPS)        │
│        └─ Uses K8s Secret for API key    │
│                                           │
│ K8s Secret: ai-service-secrets            │
│  └─ Stores DEEPSEEK_API_KEY              │
│     └─ Never logged or exposed           │
│     └─ Mounted only in ai-service pod    │
└────────────────────────────────────────────┘
```

---

**Technical Reference Version:** 1.0  
**Last Updated:** March 2026
