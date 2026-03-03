# How to Use the Final Pipeline Generation Workflow

This guide shows you how to actually USE the complete system to generate CI/CD pipelines from code changes.

## Quick Overview

**What the workflow does**:
1. You push code to GitHub (or send test webhook locally)
2. GitHub webhook → ngrok tunnel → webhook service receives it
3. Webhook service extracts the code diff and sends to AI service
4. AI service calls DeepSeek API with the diff
5. DeepSeek generates a GitHub Actions YAML pipeline
6. Pipeline is logged and ready to use

**Time needed**: ~30 minutes one-time setup, then 10 seconds per pipeline generation

---

## Step 1: Get DeepSeek API Key (5 minutes)

**What you're doing**: Getting credentials to access DeepSeek's LLM API

### Option A: If you have a DeepSeek account
1. Visit https://platform.deepseek.com/
2. Log in to your account
3. Click **API Keys** in sidebar
4. Click **Create New Key**
5. Copy the key (format: `sk-xxxxxxxxxxxxx`)
6. Save it somewhere safe (we'll use it in Step 2)

### Option B: If you don't have a DeepSeek account
1. Visit https://platform.deepseek.com/
2. Click **Sign Up**
3. Create account (email, password)
4. Verify email
5. Go to **API Keys**
6. Create new key
7. Copy and save the key

**✅ You now have**: A DeepSeek API key like `sk-1234567890abcdef`

---

## Step 2: Create Kubernetes Secret (2 minutes)

**What you're doing**: Storing the API key securely so AI service can access it

### Create the secret file

Create file: `k8s/ai-service-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-service-secrets
  namespace: default
type: Opaque
stringData:
  DEEPSEEK_API_KEY: "sk-YOUR_API_KEY_HERE"
```

**Replace `sk-YOUR_API_KEY_HERE`** with your actual API key from Step 1.

**Example** (with fake key):
```yaml
stringData:
  DEEPSEEK_API_KEY: "sk-1234567890abcdefghijklmnopqrstuvwxyz"
```

### Apply the secret to Kubernetes

```powershell
kubectl apply -f k8s/ai-service-secret.yaml
```

### Verify it was created
```powershell
kubectl get secrets
# Should show: ai-service-secrets
```

**✅ You now have**: API key stored in Kubernetes secret

---

## Step 3: Update and Deploy Code (5 minutes)

**What you're doing**: The code changes are already done. Now deploy them.

### Rebuild the webhook service Docker image

The webhook service code has been updated to call `/generate-pipeline`. Rebuild it:

```powershell
# From workspace root
docker build -t webhook-service:latest ./webhook_service
```

**Wait for it to finish** (should say "Successfully tagged webhook-service:latest")

### Restart both services

```powershell
# Restart webhook service (will use new image)
kubectl rollout restart deployment/webhook-service

# Give it 10 seconds to restart
Start-Sleep -Seconds 10

# Verify pods are running (should show 2/2 Ready)
kubectl get pods -l app=webhook-service
```

### Restart AI service (to load the secret)

```powershell
kubectl rollout restart deployment/ai-service

# Verify (should show 1/1 Ready)
kubectl get pods -l app=ai-service
```

**✅ You now have**: Updated services running with API key loaded

---

## Step 4: Trigger the Workflow (Choose One)

### Option A: Test Locally (Recommended first)

**What this does**: Sends a test webhook to your local service to verify everything works before using real GitHub.

#### Run the local test

```powershell
# This sends a test webhook to your webhook service
$payload = @{
    repository = @{ full_name = "test-org/test-repo" }
    head_commit = @{ 
        id = "abc123def456"
        message = "Add new feature for user authentication"
    }
    diff = @"
diff --git a/src/main.py b/src/main.py
index 1234567..abcdefg 100644
--- a/src/main.py
+++ b/src/main.py
@@ -1,10 +1,15 @@
import os
+import logging
 
def main():
+    logger = logging.getLogger(__name__)
     print("Hello")
+    logger.info("Application started")
"@
} | ConvertTo-Json

Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
    -Method POST `
    -Body $payload `
    -ContentType "application/json"
```

#### Watch the logs

Open a separate PowerShell window:

```powershell
# Watch webhook service logs
kubectl logs -f -l app=webhook-service --all-containers=true
```

#### Look for these log messages (in order)

1. **"Received webhook for repository: test-org/test-repo"**
   - Webhook service received your test

2. **"Processing webhook payload"**
   - Service extracted the diff

3. **"Calling AI service at http://ai-service:8000/generate-pipeline"**
   - Service is calling AI

4. **"AI service response received successfully"**
   - AI service responded

5. **"Generated CI/CD Pipeline:"** followed by YAML content
   - SUCCESS! Pipeline was generated

#### Example log output

```
2026-03-03T10:15:23 INFO Received webhook for repository: test-org/test-repo
2026-03-03T10:15:23 INFO Processing webhook payload
2026-03-03T10:15:23 INFO Extracting diff from commit abc123def456
2026-03-03T10:15:23 INFO Calling AI service at http://ai-service:8000/generate-pipeline
2026-03-03T10:15:28 INFO AI service response received successfully
2026-03-03T10:15:28 INFO Generated CI/CD Pipeline:
name: CI/CD Pipeline
on:
  push:
    branches: [ main ]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: python -m pytest
  deploy:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - name: Deploy to production
        run: echo "Deploying..."
```

**✅ If you see these messages in order**: Your workflow is working perfectly!

---

### Option B: Use Real GitHub Webhooks (Optional)

**Prerequisites**: 
- Local test (Option A) is passing
- GitHub repository set up
- ngrok running with tunnel

#### 1. Get your ngrok URL

In the ngrok terminal, look for:
```
https://abc123.ngrok-free.dev
```

#### 2. Configure GitHub webhook

1. Go to your GitHub repository
2. **Settings** → **Webhooks** → **Add webhook**
3. **Payload URL**: `https://abc123.ngrok-free.dev/webhook/github`
4. **Content type**: `application/json`
5. **Which events?**: Select **Push events**
6. Click **Add webhook**

#### 3. Trigger the workflow

Push a commit to your repository:
```powershell
git add .
git commit -m "Test feature: added new authentication module"
git push
```

#### 4. Watch results

Check logs:
```powershell
kubectl logs -f -l app=webhook-service
```

Look for the same log messages as Option A.

Check GitHub webhook delivery:
- Go to repo **Settings** → **Webhooks**
- Click the webhook you created
- Scroll to **Recent Deliveries**
- Should show green ✅ status code 200

---

## What Happens Next

Once the pipeline is generated and logged, you have several options:

### Option 1: Use the generated YAML directly
Copy the YAML from the logs and save it to `.github/workflows/pipeline.yaml` in your repo:

```powershell
# Create workflow directory
mkdir -p .github/workflows

# Create the workflow file with the generated YAML
@"
name: CI/CD Pipeline
on:
  push:
    branches: [ main ]
jobs:
  test:
    runs-on: ubuntu-latest
    ...
"@ | Out-File -FilePath ".github/workflows/pipeline.yaml"

git add .github/workflows/pipeline.yaml
git commit -m "Add auto-generated CI/CD pipeline"
git push
```

### Option 2: Automate saving the pipeline
Modify the webhook service to automatically save generated pipelines to a GitHub repo (advanced).

### Option 3: Use the pipeline while testing
The generated YAML is valid GitHub Actions syntax and ready to use immediately.

---

## Troubleshooting

### Problem: Logs show health check errors
```
GET /health returned 404
```
**Solution**: Pod crashed. Check pod logs:
```powershell
kubectl logs -l app=webhook-service
```

### Problem: "AI service response received successfully" but no pipeline in logs
**Possible causes**:
- DeepSeek API key is invalid
- DeepSeek API is unreachable
- Diff is empty

**Check**:
```powershell
# Verify secret exists
kubectl get secrets ai-service-secrets

# View AI service logs
kubectl logs -l app=ai-service
```

### Problem: Webhook returns 500 error
Check the logs:
```powershell
kubectl logs -l app=webhook-service --tail=50
```

Look for Python exceptions showing what failed.

### Problem: ngrok shows "ERR_NGROK_8012"
Webhook service is down. Verify pods:
```powershell
kubectl get pods -l app=webhook-service
# Should show 2/2 Ready for both pods

# If CrashLoopBackOff, check logs:
kubectl logs -l app=webhook-service
```

---

## Complete Workflow Summary

```
You (or GitHub)
    ↓
    Send webhook with code diff
    ↓
Webhook Service
    ├─ Receives webhook (returns 200 immediately)
    ├─ Extracts diff from payload
    ├─ Queues background task
    ↓
Background Task (async)
    ├─ Calls AI Service: /generate-pipeline
    ├─ Passes: {diff, repository, commit_message}
    ↓
AI Service
    ├─ Receives request
    ├─ Calls DeepSeek API with diff
    ├─ DeepSeek generates GitHub Actions YAML
    ├─ Returns YAML to webhook service
    ↓
Webhook Service (logs result)
    ├─ Logs: "Generated CI/CD Pipeline:"
    ├─ Logs: YAML content
    ├─ Done
    ↓
You
    └─ Copy the YAML from logs → save to .github/workflows/
```

---

## Success Criteria

You know the workflow is working when:

✅ Local test sends webhook and receives 200 OK response  
✅ Logs show "Generated CI/CD Pipeline:" message  
✅ YAML pipeline is visible in logs  
✅ Pipeline is valid GitHub Actions syntax  
✅ (Optional) GitHub webhook delivery shows green ✅  

---

## Next Steps

1. **Right now**: Run Option A (local test) from Step 4
2. **If successful**: Run `kubectl logs` and copy the generated YAML
3. **Then**: Save YAML to `.github/workflows/pipeline.yaml`
4. **Then**: Push to GitHub to activate the workflow
5. **Optional**: Set up real GitHub webhooks using Option B for automation

---

## Questions?

- **"Where do I find the API key?"** - In the logs as "Generated CI/CD Pipeline:" message
- **"Can I modify the generated pipeline?"** - Yes, it's just YAML. Edit it before using.
- **"What if the pipeline is incomplete?"** - Adjust the prompt in AI service code to be more specific
- **"Can I generate multiple pipelines?"** - Yes, send multiple webhooks (one per code change)

