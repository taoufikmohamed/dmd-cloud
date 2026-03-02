# 🏗️ System Architecture & Data Flow

## Complete System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         GITHUB                                  │
│  (Your Repository - taoufikmohamed/dmd-cloud)                   │
│                                                                 │
│  Developer pushes code with changes                             │
│  GitHub hooks webhook delivery system                           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ POST with:
                         │ - repository name
                         │ - commit message
                         │ - code diff ← KEY DATA
                         │ - other metadata
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NGROK TUNNEL (Public)                        │
│             https://abc123.ngrok-free.dev                       │
│      (Exposes localhost:8001 to the internet)                   │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ HTTP Forwarding
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│               KUBERNETES MINIKUBE CLUSTER                        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │        Webhook Service (Port 8001)                       │  │
│  │        FastAPI Application                              │  │
│  │                                                          │  │
│  │    ┌─────────────────────────────────────────────┐      │  │
│  │    │ POST /webhook/github                        │      │  │
│  │    │ 1. Receive request with diff                │      │  │
│  │    │ 2. Return 200 OK immediately ⚡ (<100ms)    │      │  │
│  │    │ 3. Queue background task                    │      │  │
│  │    └─────────────────────────────────────────────┘      │  │
│  │                         │                                │  │
│  │    Background Task      │                                │  │
│  │    (Async Processing)   │                                │  │
│  │                         ▼                                │  │
│  │    ┌─────────────────────────────────────────────┐      │  │
│  │    │ 1. Extract diff from payload                │      │  │
│  │    │ 2. Extract repo name                        │      │  │
│  │    │ 3. Extract commit message                   │      │  │
│  │    │ 4. Prepare request for AI service           │      │  │
│  │    └────────────────┬────────────────────────────┘      │  │
│  │                     │                                    │  │
│  │    POST /generate-pipeline (HTTP)                        │  │
│  │                     │                                    │  │
│  │                     ▼                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                     │                                           │
│  ┌──────────────────┴──────────────────────────────────────┐   │
│  │        AI Service (Port 8000)                          │   │
│  │        FastAPI Application                            │   │
│  │                                                        │   │
│  │    ┌────────────────────────────────────────────┐     │   │
│  │    │ POST /generate-pipeline                    │     │   │
│  │    │ 1. Receive diff + metadata                │     │   │
│  │    │ 2. Create prompt for DeepSeek            │     │   │
│  │    │ 3. Call DeepSeek API (HTTPS)             │     │   │
│  │    │ 4. Return response to webhook service    │     │   │
│  │    └────────────────┬───────────────────────────┘     │   │
│  │                     │                                 │   │
│  │    HTTPS API Call   │                                 │   │
│  │                     ▼                                 │   │
│  └──────────────────────────────────────────────────────────┘  │
│                     │                                           │
└─────────────────────┼───────────────────────────────────────────┘
                      │
                      │ HTTPS (Internet)
                      │
                      ▼
    ┌──────────────────────────────────────┐
    │    DeepSeek API                      │
    │    (LLM - Large Language Model)      │
    │                                      │
    │  Receives:                           │
    │  - Your code diff                    │
    │  - Repository name                   │
    │  - Request to generate pipeline      │
    │                                      │
    │  Generates:                          │
    │  - GitHub Actions YAML workflow      │
    │  - Complete CI/CD pipeline           │
    │  - Best practices for your language  │
    │                                      │
    │  Returns:                            │
    │  - Generated YAML file               │
    │                                      │
    └──────────────────┬───────────────────┘
                       │
                       │ JSON Response with YAML
                       │
                       ▼
    ┌──────────────────────────────────────┐
    │  AI Service Receives Pipeline        │
    │                                      │
    │  Extracts content from response      │
    │  Returns to Webhook Service          │
    └──────────────────┬───────────────────┘
                       │
                       ▼
    ┌──────────────────────────────────────┐
    │  Webhook Service Receives Pipeline   │
    │                                      │
    │  Logs:                               │
    │  "Generated CI/CD Pipeline:"         │
    │  [Full YAML content]                 │
    │                                      │
    │  ✅ DONE!                            │
    └──────────────────────────────────────┘
```

---

## Data Transformation Flow

### 🔄 How Data Changes at Each Step

#### 1️⃣ GitHub Webhook (Input)
```json
{
  "repository": {"full_name": "taoufikmohamed/dmd-cloud"},
  "head_commit": {"message": "Fix bug in main.py"},
  "diff": "diff --git a/main.py b/main.py\nindex...\n-old code\n+new code"
}
```

#### 2️⃣ Webhook Service Extracts
```json
{
  "diff": "diff --git a/main.py b/main.py\nindex...\n-old code\n+new code",
  "repository": "taoufikmohamed/dmd-cloud",
  "commit_message": "Fix bug in main.py"
}
```

#### 3️⃣ AI Service Creates Prompt
```
Analyze this git diff and generate a GitHub Actions YAML pipeline:

diff --git a/main.py b/main.py
index...
-old code
+new code
```

#### 4️⃣ DeepSeek API Generates
```yaml
name: Python Bug Fix CI/CD
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
      - run: pip install -r requirements.txt
      - run: pytest tests/
      - run: flake8 main.py
  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy fix
        run: |
          python -m pip install --upgrade pip
          python -m build
```

#### 5️⃣ Webhook Service Logs
```
INFO:main:Generated CI/CD Pipeline:
name: Python Bug Fix CI/CD
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    ...
```

---

## Request/Response Timeline

```
t=0ms          ← GitHub sends webhook POST
               │
               ▼
t=10ms         Webhook Service receives
               │
               ├─ Log: "Received webhook"
               │
               ├─ Background task queued
               │
               ▼
t=50ms         Webhook Service responds
               │
               ├─ HTTP 200 OK
               ├─ Message: "queued for pipeline generation"
               │
               ▼
t=100ms        ← GitHub sees success ✅
               │   (No need to wait further)
               │
               │ Meanwhile, background task continues...
               │
               ▼
t=500ms        Background task processes
               │
               ├─ Log: "Processing webhook"
               ├─ Log: "Extracted diff"
               │
               ▼
t=1000ms       Call AI Service
               │
               ├─ POST /generate-pipeline
               ├─ Log: "Calling AI service"
               │
               ▼
t=2000ms       AI Service calls DeepSeek
               │
               ├─ DeepSeek starts processing...
               │
               ▼
t=12000ms      DeepSeek responds
               │
               ├─ Generated YAML pipeline
               │
               ▼
t=13000ms      Webhook logs result
               │
               ├─ Log: "Successfully generated"
               ├─ Log: "Generated CI/CD Pipeline:"
               ├─ Log: [Full YAML content]
               │
               ▼
DONE! ✅       Total: ~13 seconds
               (but GitHub only waited 100ms)
```

---

## Component Responsibilities

### 📡 GitHub
- Sends webhook with:
  - Repository name
  - Commit message
  - **Code diff** (the actual changes)
- Expects response within 30 seconds

### 🔌 Webhook Service
**Responsibility:** Act as bridge + coordinator

1. **Receive** webhook from GitHub (< 100ms)
2. **Respond** with 200 OK to GitHub (don't keep them waiting)
3. **Extract** relevant data from payload
4. **Call** AI service's `/generate-pipeline` endpoint
5. **Log** results for visibility

**Key feature:** Returns instantly, processes in background

### 🤖 AI Service
**Responsibility:** Interface with AI

1. **Receive** diff + metadata from webhook
2. **Create** appropriate prompt
3. **Call** DeepSeek API with diff
4. **Parse** response (get content from `choices[0].message.content`)
5. **Return** to webhook service

### 🧠 DeepSeek API
**Responsibility:** Generate pipeline

1. **Receive** code diff + generation request
2. **Analyze** what the code does
3. **Determine** testing needs, build steps, deployment
4. **Generate** complete GitHub Actions YAML
5. **Return** as JSON response

---

## System Characteristics

### ⚡ Performance
- **Webhook response:** < 100ms (instant)
- **AI generation:** 10-30 seconds (background)
- **Total time:** 10-30 seconds (but GitHub doesn't wait)
- **Timeout risk:** None (GitHub already happy)

### 🔄 Reliability
- **Auto-retry:** 3 attempts with exponential backoff
- **Backoff timing:** 1s, 2s, 4s delays
- **Max wait:** 7 seconds for retries
- **Fallback:** All errors logged, pipeline may not be generated but webhook still succeeds

### 📊 Scalability
- **Concurrent webhooks:** Multiple can be processed simultaneously
- **Pod replicas:** 2 webhook service pods, 1 AI service pod
- **Async processing:** Non-blocking, uses FastAPI async/await
- **Queue:** Kubernetes job queue handles concurrent background tasks

### 🔒 Security
- **DeepSeek API key:** Stored in Kubernetes Secret (not in code)
- **All HTTPS:** DeepSeek calls use HTTPS
- **No data stored:** Logs are ephemeral (pods ephemeral storage)
- **Network isolation:** AI service is internal (ClusterIP), webhook is external (NodePort)

---

## Integration Points

### 📍 External Integrations
1. **GitHub** (incoming)
   - Sends webhook events
   - Expects 200 response
   
2. **DeepSeek API** (outgoing)
   - Requires API key
   - Generates AI content
   - Internet connectivity required

### 📍 Internal Integrations
1. **Webhook Service ↔ AI Service** (HTTP)
   - Kubernetes internal network
   - DNS: `http://ai-service:8000`
   - Endpoint: `/generate-pipeline`

2. **Kubernetes Secrets** (configuration)
   - Stores DeepSeek API key securely
   - Referenced by AI service as environment variable

---

## Deployment Units

### 🐳 Webhook Service Pod
- **Image:** `webhook-service:latest`
- **Port:** 8001 (exposed to internet via NodePort)
- **Replicas:** 2 (for redundancy)
- **Mounts:** None (stateless)
- **Resources:** 256Mi memory cap, 500m CPU cap

### 🐳 AI Service Pod
- **Image:** `ai-service:latest`
- **Port:** 8000 (internal only, ClusterIP)
- **Replicas:** 1 (AI service is stateless, can scale if needed)
- **Secrets:** AI service secret (DeepSeek API key)
- **Resources:** 256Mi memory cap, 500m CPU cap

### 📦 Kubernetes Service
- **Webhook Service:** NodePort (external access)
- **AI Service:** ClusterIP (internal only)
- **Networking:** Both in same cluster, direct communication

---

## What Success Looks Like

```
Github Push
    ↓
✅ Webhook receives and responds (100ms)
    ↓
✅ Background processes diff
    ↓
✅ AI service called
    ↓
✅ DeepSeek generates pipeline
    ↓
✅ Logs show: "Generated CI/CD Pipeline:"
    ↓
✅ YAML pipeline visible in logs
    ↓
✅ RESULT: Automated pipeline generation!
```

---

## Key Takeaway

Your system is a **three-tier architecture**:

1. **Frontend Tier:** Webhook Service (FastAPI, public)
2. **Logic Tier:** AI Service (FastAPI, internal)
3. **AI Tier:** DeepSeek API (LLM, external)

Each tier has a specific responsibility:
- Webhook: Receive and coordinate
- AI Service: Process and format
- DeepSeek: Generate intelligence

All communicate via HTTP/HTTPS, all stateless, all easily scalable! 🚀
