# 🤖 Complete Workflow: GitHub → Webhook → AI → Pipeline

## Overview

Your system should work like this:

```
GitHub Push
    ↓
Webhook Service (receives push event)
    ↓
Returns 200 OK immediately ⚡
    ↓
Background Task: Extract diff + call AI service
    ↓
AI Service: Call DeepSeek API with code diff
    ↓
AI generates CI/CD pipeline YAML
    ↓
Pipeline logged and ready to use
```

---

## ✅ What Just Changed

I updated the **webhook service** to:
1. Extract the **diff** from GitHub webhook payload
2. Call the AI service's **`/generate-pipeline`** endpoint (not just POST to root)
3. Send proper data: `{"diff": "...", "repository": "...", "commit_message": "..."}`
4. Log the AI-generated pipeline for review

---

## 🔧 Step 1: Set Up DeepSeek API Key

### 1A: Create Secret File
Create file `k8s/ai-service-secret.yaml` (do NOT commit):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-service-secrets
  namespace: default
type: Opaque
stringData:
  DEEPSEEK_API_KEY: "sk-xxxxx_YOUR_DEEPSEEK_KEY_HERE_xxxxx"
```

### 1B: Get DeepSeek API Key
1. Go to: https://platform.deepseek.com/
2. Sign up or login
3. Create API key
4. Copy the key
5. Paste into secret file above

### 1C: Apply Secret to Kubernetes
```bash
kubectl apply -f k8s/ai-service-secret.yaml
```

**Verify:**
```bash
kubectl get secrets
# Should see: ai-service-secrets
```

---

## 🐳 Step 2: Rebuild Webhook Service (New Code)

The webhook service code changed to properly call the AI service. You need to rebuild:

```powershell
# 1. Make sure you're using minikube docker
minikube docker-env --shell powershell | Invoke-Expression

# 2. Build new image
docker build -t webhook-service:latest ./webhook_service

# 3. Restart deployment to use new image
kubectl rollout restart deployment/webhook-service

# 4. Wait for new pods
kubectl get pods -l app=webhook-service -w
```

**Wait for:**
```
webhook-service-xxxxx   1/1     Running   0
webhook-service-xxxxx   1/1     Running   0
```

---

## 🚀 Step 3: Rebuild AI Service (If Needed)

Check if AI service code is correct:

```bash
kubectl logs -l app=ai-service --tail=5
```

If it shows errors, rebuild:

```powershell
minikube docker-env --shell powershell | Invoke-Expression
docker build -t ai-service:latest ./ai_service
kubectl rollout restart deployment/ai-service
```

---

## 🧪 Step 4: Test End-to-End Locally

### Test 4A: Verify Webhook Service is Updated
```powershell
kubectl logs -l app=webhook-service --tail=5
```

Should show:
```
INFO:     Started server process
INFO:     Application startup complete
```

### Test 4B: Send Test Webhook
```powershell
$payload = Get-Content test-webhook.json -Raw

Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
  -Method POST `
  -ContentType "application/json" `
  -Body $payload `
  -UseBasicParsing
```

**Expected Response:**
```
Status Code: 200
Message: "Webhook received and queued for pipeline generation"
```

### Test 4C: Watch Logs for AI Generation
Open **new terminal** and watch logs:

```bash
kubectl logs -f -l app=webhook-service --all-containers=true
```

You should see activity like:

```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Processing webhook payload (attempt 1/4)
INFO:main:Extracted diff from repository: taoufikmohamed/dmd-cloud
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: CI/CD Pipeline
on:
  push:
    branches: [main, develop]
jobs:
  build:
    runs-on: ubuntu-latest
    ...
```

**✅ If you see "Successfully generated pipeline" → IT WORKED!**

---

## 🔍 What Each Component Expects

### GitHub Webhook Payload (What you send)
```json
{
  "repository": {
    "full_name": "owner/repo"
  },
  "head_commit": {
    "message": "Your commit message"
  },
  "diff": "diff --git a/file.py ...\n..."  // ← This is KEY
}
```

### Webhook Service → AI Service (What we send)
```json
{
  "diff": "diff --git a/file.py ...\n...",
  "repository": "owner/repo",
  "commit_message": "Your commit message"
}
```

### AI Service → DeepSeek API (What AI service sends)
```
"Analyze this git diff and generate a GitHub Actions YAML pipeline:

diff --git a/file.py b/file.py
..."
```

### DeepSeek API Response (What we get back)
```json
{
  "choices": [
    {
      "message": {
        "content": "name: CI/CD Pipeline\non:\n  push:\n..."
      }
    }
  ]
}
```

### Webhook Service Log Output (What gets logged)
```
Generated CI/CD Pipeline:
name: CI/CD Pipeline
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: echo "Building..."
```

---

## ✅ Success Indicators

### In Webhook Logs (kubectl logs)
✅ You're successful when you see:
```
INFO:main:Received webhook for repository
INFO:main:Processing webhook payload
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: CI/CD Pipeline
```

### In AI Service Logs
```
INFO:     "POST /generate-pipeline HTTP/1.1" 200
```

### Quick Check Command
```bash
kubectl logs -l app=webhook-service | grep -i "generated\|pipeline"
```

If you see pipeline content, **it works!** ✅

---

## 🐛 Troubleshooting

### Issue: "Error calling AI service: HTTPStatusError: 404"

**Cause:** Webhook is calling wrong endpoint

**Solution:** 
- Check webhook code is updated: `kubectl describe pod <WEBHOOK_POD>`
- Rebuild webhook service (step 2 above)

---

### Issue: "DEEPSEEK_API_KEY is not configured"

**Cause:** AI service secret not created

**Solution:**
```bash
# Check if secret exists
kubectl get secrets ai-service-secrets

# If not, create it
kubectl apply -f k8s/ai-service-secret.yaml

# Restart AI service
kubectl rollout restart deployment/ai-service
```

---

### Issue: AI logs show "DeepSeek API is unavailable"

**Causes:**
1. Invalid API key
2. DeepSeek API is down
3. Network issue

**Solution:**
1. Verify API key is valid: https://platform.deepseek.com/
2. Check DeepSeek status page
3. Test connection from AI pod:
   ```bash
   kubectl exec -it <AI_POD> -- curl https://api.deepseek.com/health
   ```

---

### Issue: AI takes > 30 seconds (times out)

**Cause:** DeepSeek API is slow

**Solution:** Increase timeout
```yaml
# In k8s/ai-deployment.yaml, add:
env:
- name: DEEPSEEK_TIMEOUT_SECONDS
  value: "120"
```

Then restart:
```bash
kubectl apply -f k8s/ai-deployment.yaml
```

---

## 📊 Verification Checklist

### Prerequisites
- [ ] DeepSeek API key created
- [ ] Secret applied to Kubernetes
- [ ] Webhook service rebuilt with new code
- [ ] AI service running

### Local Testing
- [ ] Send test webhook to endpoint
- [ ] Webhook responds with 200 ✅
- [ ] Logs show "Processing webhook payload"
- [ ] Logs show "Calling AI service"
- [ ] Logs show "Successfully generated pipeline"
- [ ] Pipeline YAML visible in logs

### One More Time: Complete Flow
```
1. Send POST /webhook/github ← START HERE
   ↓
2. Response: 200 OK with "queued for pipeline generation"
   ↓
3. Background task starts (async)
   ↓
4. Extract diff from payload (log shows this)
   ↓
5. Call AI service /generate-pipeline (log shows URL)
   ↓
6. AI calls DeepSeek API (may take 10-30 seconds)
   ↓
7. DeepSeek returns generated pipeline
   ↓
8. Logs show: "Generated CI/CD Pipeline:" + YAML content
   ↓
   ✅ DONE (took 10-30 seconds total, but webhook returned immediately)
```

---

## 📝 Test with Real GitHub Webhook

Once local tests pass:

1. Configure GitHub webhook:
   ```
   Payload URL: https://YOUR_NGROK_URL/webhook/github
   ```

2. Make a real push to your repository
3. Watch webhook logs in real-time:
   ```bash
   kubectl logs -f -l app=webhook-service --all-containers=true
   ```

4. Within 10-30 seconds, should see:
   ```
   INFO:main:Generated CI/CD Pipeline:
   name: GitHub Actions Workflow
   ...
   ```

---

## 🎯 What You'll Get

Once everything works, your system generates CI/CD pipelines automatically:

**Input (from GitHub):**
```diff
diff --git a/main.py
+def new_feature():
+    return "hello"
```

**Output (from AI in logs):**
```yaml
name: Test and Deploy
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
      - run: pip install pytest
      - run: pytest
  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: echo "Deploying..."
```

---

## 🚀 Next Steps

1. ✅ Verify DeepSeek API key works
2. ✅ Rebuild webhook service
3. ✅ Test locally with curl/Postman
4. ✅ Watch logs for "Generated CI/CD Pipeline"
5. ✅ Test with real GitHub webhooks
6. ✅ Save generated pipelines for team review

---

**When you see "Successfully generated pipeline" in logs, you're done!** 🎉
