# 📊 Data Flow: Input → Process → Output

## Complete Pipeline Data Flow with Examples

---

## Step 1️⃣: GitHub Sends Webhook

### 📤 What GitHub Sends (Input)

```json
POST https://your-webhook-url/webhook/github

{
  "repository": {
    "full_name": "taoufikmohamed/dmd-cloud"
  },
  "head_commit": {
    "id": "abc123def456",
    "message": "Add new feature"
  },
  "diff": "diff --git a/main.py b/main.py\nindex e69de29..abc1234 100644\n--- a/main.py\n+++ b/main.py\n@@ -0,0 +1,10 @@\n+def hello():\n+    return 'Hello World'\n+\n+if __name__ == '__main__':\n+    print(hello())"
}
```

### ⏱️ Webhook Service Response (Immediate)

**Time:** < 100ms ⚡

```json
HTTP 200 OK

{
  "status": "received",
  "message": "Webhook received and queued for pipeline generation"
}
```

### 📝 What Gets Logged (Step 1)

```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Commit message: Add new feature
```

✅ **GitHub sees:** Successful delivery (green checkmark)  
✅ **GitHub waits:** Done! No need to wait for pipeline

---

## Step 2️⃣: Webhook Service Processes Async

### 🔄 What Webhook Service Does

**Inside the background task (asynchronously):**

1. Extract from payload:
   - Repository: `taoufikmohamed/dmd-cloud`
   - Commit message: `Add new feature`
   - **Diff:** The actual code changes

2. Create AI service request:

### 📤 What Gets Sent to AI Service

**Endpoint:** `POST http://ai-service:8000/generate-pipeline`

**Payload:**
```json
{
  "diff": "diff --git a/main.py b/main.py\nindex e69de29..abc1234 100644\n--- a/main.py\n+++ b/main.py\n@@ -0,0 +1,10 @@\n+def hello():\n+    return 'Hello World'\n+\n+if __name__ == '__main__':\n+    print(hello())",
  "repository": "taoufikmohamed/dmd-cloud",
  "commit_message": "Add new feature"
}
```

### 📝 What Gets Logged (Step 2)

```
INFO:main:Processing webhook payload (attempt 1/4)
INFO:main:Extracted diff (547 chars) from repository: taoufikmohamed/dmd-cloud
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
```

✅ **Webhook is still responsive**  
✅ **GitHub already considers this successful**

---

## Step 3️⃣: AI Service Calls DeepSeek

### 🤖 What AI Service Does

Takes the diff and creates a prompt for DeepSeek:

### 📤 What Gets Sent to DeepSeek API

**Endpoint:** `https://api.deepseek.com/v1/chat/completions`

**Payload:**
```json
{
  "model": "deepseek-coder",
  "messages": [
    {
      "role": "user",
      "content": "Analyze this git diff and generate a GitHub Actions YAML pipeline:\n\ndiff --git a/main.py b/main.py\nindex e69de29..abc1234 100644\n--- a/main.py\n+++ b/main.py\n@@ -0,0 +1,10 @@\n+def hello():\n+    return 'Hello World'\n+..."
    }
  ],
  "temperature": 0.2
}
```

### ⏱️ DeepSeek Processes

**Time:** 10-30 seconds (this is why async is important!)

DeepSeek AI analyzes:
- What code was added/changed
- What language (Python in this case)
- What testing/building steps might be needed
- Generates appropriate GitHub Actions workflow

---

## Step 4️⃣: DeepSeek Returns Pipeline

### 📥 What DeepSeek Returns

**Response:**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1709500000,
  "model": "deepseek-coder",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "name: Python CI/CD Pipeline\non:\n  push:\n    branches: [main, develop]\n  pull_request:\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v3\n      - uses: actions/setup-python@v4\n        with:\n          python-version: '3.11'\n      - name: Install dependencies\n        run: |\n          python -m pip install --upgrade pip\n          pip install pytest\n      - name: Run tests\n        run: pytest\n  lint:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v3\n      - uses: actions/setup-python@v4\n      - name: Lint with flake8\n        run: |\n          pip install flake8\n          flake8 ."
      },
      "finish_reason": "stop"
    }
  ]
}
```

### 📝 What Gets Logged (Step 4)

```
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: Python CI/CD Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install pytest
      - name: Run tests
        run: pytest
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
      - name: Lint with flake8
        run: |
          pip install flake8
          flake8 .
```

✅ **Pipeline is now visible in logs**  
✅ **Team can review and use it**

---

## 📈 Complete Timeline

```
t=0ms     GitHub Sends Webhook
           └─ Your webhook URL receives POST with diff

t=10ms    Webhook Service Receives
           └─ FastAPI routes to /webhook/github endpoint
           └─ Logs: "Received webhook for repository"

t=50ms    Webhook Service Returns 200
           └─ Returns immediately to GitHub
           └─ GitHub marks as success ✅
           └─ Background task queued

t=100ms   Background Task Starts
           └─ Extracts diff from payload
           └─ Logs: "Processing webhook payload"
           └─ Logs: "Extracted diff"

t=500ms   Call to AI Service
           └─ POSTs to http://ai-service:8000/generate-pipeline
           └─ Logs: "Calling AI service"

t=600ms   AI Service Calls DeepSeek
           └─ Sends diff + prompt to DeepSeek API
           └─ Waits for response...

t=10000ms DeepSeek Processes
           └─ AI analyzes code
           └─ AI generates GitHub Actions YAML
           └─ (takes 10-20 seconds total)

t=15000ms DeepSeek Responds
           └─ Returns generated pipeline
           └─ AI service logs pipeline
           └─ Logs: "Successfully generated pipeline"
           └─ Logs: "Generated CI/CD Pipeline:" + YAML

TOTAL:    ~15 seconds to complete
WAIT:     100ms (GitHub already happy)
```

---

## 🔄 What Happens if AI Service Fails

### ❌ Scenario: AI Service Timeout

```
t=100ms   Background Task Starts
t=500ms   Call to AI Service (attempt 1)
t=5500ms  Timeout! (5 second timeout)
          └─ Log: "Timeout calling AI service"
          └─ Log: "Retrying in 1 seconds..."

t=6500ms  Call to AI Service (attempt 2)
t=11500ms Timeout! (5 second timeout)
          └─ Log: "Retrying in 2 seconds..."

t=13500ms Call to AI Service (attempt 3)
t=18500ms Timeout! (5 second timeout)
          └─ Log: "Retrying in 4 seconds..."

t=22500ms Call to AI Service (attempt 4)
t=27500ms Timeout! (5 second timeout)
          └─ Log: "Max retries exceeded"
```

✅ **GitHub still successful** (responded at t=50ms)  
❌ **Pipeline not generated** (but retried 3 times)

---

## 🎯 Success Indicators

### When Looking at Logs

#### ✅ Success Case (Full Pipeline Generated)
```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Processing webhook payload (attempt 1/4)
INFO:main:Extracted diff (547 chars) from repository: taoufikmohamed/dmd-cloud
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: Python CI/CD Pipeline
on:
  push:
    branches: [main]
...
```

#### ⚠️ Retry Case (AI Service Slow/Down)
```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Processing webhook payload (attempt 1/4)
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
ERROR:main:Error calling AI service: HTTPStatusError: 404
INFO:main:Retrying in 1 seconds...
INFO:main:Processing webhook payload (attempt 2/4)
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: Python CI/CD Pipeline
...
```

---

## 📋 Key Log Messages to Look For

| Log Message | What It Means | Status |
|-------------|---------------|--------|
| `Received webhook for repository` | Webhook endpoint was called | ✅ Starting |
| `Processing webhook payload (attempt 1/4)` | Background task started | ✅ Processing |
| `Extracted diff (...) from repository` | Diff extracted from payload | ✅ Data ready |
| `Calling AI service: POST .../generate-pipeline` | Calling AI for pipeline | ✅ Sending to AI |
| `Successfully generated pipeline from AI service` | AI returned response | ✅ Got response |
| `Generated CI/CD Pipeline:` | Pipeline logged (next lines are YAML) | ✅ SUCCESS! |
| (followed by YAML content) | Actual generated GitHub Actions workflow | ✅ Pipeline ready |

---

## ❌ Error Indicators

| Error Message | Cause | Fix |
|---------------|-------|-----|
| `Error calling AI service: HTTPStatusError: 404` | Webhook calling wrong endpoint | Rebuild webhook service |
| `DEEPSEEK_API_KEY is not configured` | Secret not created | Create secret with API key |
| `DeepSeek API is unavailable` | Invalid API key or API down | Check API key or wait for API |
| `Timeout calling AI service` | AI service too slow | Increase timeout, check AI service |
| No "Generated CI/CD Pipeline" message | Pipeline generation failed | Check logs, verify API key |

---

## 🎬 Live Example

**Send this webhook:**
```bash
curl -X POST http://localhost:8001/webhook/github \
  -H "Content-Type: application/json" \
  -d '{
    "repository": {"full_name": "taoufikmohamed/dmd-cloud"},
    "head_commit": {"message": "Add feature"},
    "diff": "diff --git a/main.py\n+def new_feature():\n+    pass"
  }'
```

**You'll see:**
```
1. Instant response: HTTP 200
2. In logs (after 1-2 sec):  Received webhook
3. In logs (after 2-3 sec):  Extracted diff
4. In logs (after 3-5 sec):  Calling AI service
5. In logs (after 15-20 sec): Generated CI/CD Pipeline
6. In logs:                    Full YAML workflow
```

**Bottom line:** Watch the logs for "Generated CI/CD Pipeline" - that's your signal it worked! ✅

---

**You now understand the complete flow!** 🎉
