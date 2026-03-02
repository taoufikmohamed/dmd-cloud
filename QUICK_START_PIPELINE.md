# 🚀 Quick Start: Enable AI Pipeline Generation

## What You Need to Do (4 Easy Steps)

### Step 1: Get DeepSeek API Key ⏱️ 2 minutes

1. Go to: https://platform.deepseek.com/
2. Sign up / Login
3. Go to: API Keys → Create New Key
4. Copy your key (looks like: `sk-xxxxxxxxxxxxxxxxxxxx`)

---

### Step 2: Create Kubernetes Secret ⏱️ 1 minute

Create file: `k8s/ai-service-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-service-secrets
  namespace: default
type: Opaque
stringData:
  DEEPSEEK_API_KEY: "sk-YOUR_KEY_HERE"
```

Run:
```bash
kubectl apply -f k8s/ai-service-secret.yaml
```

Verify:
```bash
kubectl get secrets | grep ai-service
# Should see: ai-service-secrets
```

---

### Step 3: Rebuild Webhook Service ⏱️ 3 minutes

The code was updated to call AI service's `/generate-pipeline` endpoint.

**Option A: If Docker works**
```powershell
docker build -t webhook-service:latest ./webhook_service
kubectl rollout restart deployment/webhook-service
```

**Option B: Using minikube**
```powershell
minikube image build -t webhook-service:latest ./webhook_service
kubectl rollout restart deployment/webhook-service
```

Wait for pods:
```bash
kubectl get pods -l app=webhook-service -w
```

Should show: `1/1 Running` for both pods

---

### Step 4: Restart AI Service ⏱️ 1 minute

```bash
kubectl rollout restart deployment/ai-service
kubectl get pods -l app=ai-service
```

Should show: `1/1 Running`

---

## ✅ Test It Works

### Test 1A: Send Webhook Locally
```powershell
$payload = Get-Content test-webhook.json -Raw

Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
  -Method POST `
  -ContentType "application/json" `
  -Body $payload
```

**Expected Response:**
```
Status Code: 200
Message: "Webhook received and queued for pipeline generation"
```

### Test 1B: Watch Logs (New Terminal)
```bash
kubectl logs -f -l app=webhook-service
```

**Watch for these messages in order:**

#### Message 1 (immediate):
```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
```
✅ Webhook received

#### Message 2 (1-2 seconds):
```
INFO:main:Processing webhook payload (attempt 1/4)
INFO:main:Extracted diff from repository: taoufikmohamed/dmd-cloud
```
✅ Diff extracted

#### Message 3 (2-5 seconds):
```
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
```
✅ Calling AI service

#### Message 4 (10-30 seconds later):
```
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: CI/CD Pipeline
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
```
✅ **PIPELINE GENERATED!**

---

## 💡 What Each Message Means

| Message | What's Happening | Time |
|---------|------------------|------|
| "Received webhook" | Webhook endpoint was called | Instant |
| "Webhook received and queued" | Response sent back to GitHub | < 100ms |
| "Processing webhook payload" | Background task started | ~ 1s |
| "Extracted diff" | Git diff pulled from payload | ~ 2s |
| "Calling AI service" | Request sent to `/generate-pipeline` | ~ 3s |
| "Successfully generated pipeline" | AI service returned response | 10-30s |
| "Generated CI/CD Pipeline:" | Full YAML pipeline logged | 10-30s |

---

## 🔍 Understanding the Flow

### Before (Old Way - ❌ INCOMPLETE)
```
GitHub Push
   ↓
Webhook receives (200 OK)
   ↓
Calls AI service root endpoint (generic)
   ↓
AI service doesn't know what to do
   ↓
❌ No pipeline generated
```

### After (New Way - ✅ COMPLETE)
```
GitHub Push (with code diff)
   ↓
Webhook receives (200 OK immediately)
   ↓
Extracts diff from payload
   ↓
Calls AI service /generate-pipeline endpoint with diff
   ↓
AI service sends diff + prompt to DeepSeek API
   ↓
DeepSeek generates GitHub Actions YAML pipeline
   ↓
AI service returns pipeline
   ↓
Logs: "Generated CI/CD Pipeline:" + YAML content
   ↓
✅ Pipeline generated and logged!
```

---

## ✅ Success Checklist

### Local Testing
- [ ] Webhook responds with 200 OK
- [ ] Response message mentions "pipeline generation"
- [ ] `kubectl logs` shows "Received webhook"
- [ ] `kubectl logs` shows "Processing webhook payload"
- [ ] `kubectl logs` shows "Calling AI service"
- [ ] `kubectl logs` shows "Successfully generated pipeline"
- [ ] `kubectl logs` shows YAML pipeline content in "Generated CI/CD Pipeline" section

### GitHub Integration
- [ ] Create secret with DeepSeek key
- [ ] Rebuild webhook service
- [ ] Restart both services
- [ ] Send real GitHub webhook
- [ ] GitHub shows ✅ success
- [ ] Logs show generated pipeline

---

## 🎯 What Success Looks Like

When it's working, you'll see this in logs:

```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Commit message: Update README
INFO:main:Processing webhook payload (attempt 1/4)
INFO:main:Extracted diff (547 chars) from repository: taoufikmohamed/dmd-cloud
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: GitHub Actions Workflow
on:
  push:
    branches:
      - main
      - develop
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
          pip install -r requirements.txt
      - name: Run tests
        run: pytest
  build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v3
      - name: Build Docker image
        run: |
          docker build -t myapp:${{ github.sha }} .
```

🎉 **That's the AI-generated pipeline!**

---

## 🐛 If Something Goes Wrong

### Problem: No "Successfully generated" message

**Check 1:** Secret exists
```bash
kubectl get secrets ai-service-secrets
```
If missing, create it (Step 2 above)

**Check 2:** AI service can reach DeepSeek API
```bash
kubectl logs -l app=ai-service | tail -20
```
Look for errors about API key or connection

**Check 3:** Webhook service has new code
```bash
kubectl logs -l app=webhook-service | grep "generate-pipeline"
```
If not there, rebuild image (Step 3)

---

### Problem: "DEEPSEEK_API_KEY is not configured"

Solution:
```bash
# Create/update secret
kubectl apply -f k8s/ai-service-secret.yaml

# Restart AI service
kubectl rollout restart deployment/ai-service
```

---

### Problem: "DeepSeek API is unavailable"

Possible causes:
1. Invalid API key
2. DeepSeek API is down
3. Network connectivity issue

Check:
1. Visit https://platform.deepseek.com/ and verify API key is valid
2. Check your secret has the correct key format: `sk-xxxxx`
3. Test curl from pod (advanced):
   ```bash
   kubectl exec -it <AI_POD_NAME> -- bash
   curl https://api.deepseek.com/v1/chat/completions \
     -H "Authorization: Bearer sk-YOUR_KEY" \
     -d '{"model":"deepseek-coder"}'
   ```

---

## 📊 Timeline Example

When you send a webhook at **10:00:00**:

```
10:00:00 - Send POST webhook
10:00:00 - Response: 200 OK (< 100ms)
10:00:01 - "Processing webhook payload"
10:00:02 - "Extracted diff"
10:00:03 - "Calling AI service"
10:00:15 - DeepSeek API responds (takes ~10-15 seconds)
10:00:16 - "Successfully generated pipeline"
10:00:16 - YAML content appears in logs
```

Total visible time: 16 seconds  
Time user had to wait: 100ms ✅

---

## 🎓 Learning Points

**Why This Design?**
1. **Fast response to GitHub** (~100ms) → GitHub marks webhook as success
2. **Background processing** (10-30s) → Time for AI to generate pipeline
3. **Automatic retries** → If AI service fails, tries again
4. **Detailed logging** → Easy to debug what happened

**Why Async?**
- GitHub times out after 30 seconds
- AI generation might take 10-30 seconds
- By responding immediately, we never timeout
- Pipeline generation happens in background

---

## 🚀 Ready?

1. **Get DeepSeek key** (2 min)
2. **Create secret** (1 min)  
3. **Rebuild webhook** (3 min)
4. **Restart services** (1 min)
5. **Test locally** (1 min)
6. **Watch logs** (ongoing)
7. **See "Generated CI/CD Pipeline"** ✅

**Total time to working system: ~10 minutes**

Start with Step 1 above! 🖱️
