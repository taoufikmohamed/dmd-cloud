# DMD Cloud Project - Complete User Guide
  Diff-Managed Deployment
  DeepSeek-Managed Deployment
  Dynamic Managed Deployment

## Executive Summary

**DMD Cloud** is an automated CI/CD pipeline generator that uses GitHub webhooks and AI (DeepSeek API) to generate GitHub Actions workflows from code diffs.

**The Workflow:**
```
GitHub Webhook → DMD Webhook Service → DeepSeek AI → Generate Pipeline YAML → Auto-Save to .github/workflows/ci-cd.yml
```

Whenever you push code to GitHub, a webhook automatically triggers the system to analyze your changes and generate an optimized GitHub Actions CI/CD pipeline.

---

## Quick Start (5 Minutes)

### Prerequisites
- Minikube running with kubectl installed
- Docker configured
- DeepSeek API key (get from https://platform.deepseek.com/)

### Step 1: Create Kubernetes Secret
```powershell
kubectl create secret generic ai-service-secrets `
  --from-literal=DEEPSEEK_API_KEY="sk-your-actual-key-here" `
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 2: Deploy System
```powershell
# Build images in minikube
minikube image build -t webhook-service:latest ./webhook_service
minikube image build -t ai-service:latest ./ai_service

# Apply Kubernetes manifests
kubectl apply -f k8s/webhook-deployment.yaml
kubectl apply -f k8s/ai-deployment.yaml

# Verify all pods are running
kubectl get pods
```

### Step 3: Test Workflow
```powershell
# Start port-forward
Start-Job -ScriptBlock { kubectl port-forward service/webhook-service 8001:8001 } | Out-Null

# Send test webhook
$payload = @{
    repository = @{ full_name = "test-org/test-repo" }
    head_commit = @{ id = "abc123"; message = "Test change" }
    diff = "diff --git a/app.py\n+print('hello')"
} | ConvertTo-Json

Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
    -Method POST -Body $payload -ContentType "application/json"

# Check logs (wait 30-40 seconds for AI processing)
Start-Sleep -Seconds 40
kubectl logs -l app=webhook-service --since=2m
```

**Success:** Look for log lines:
```
INFO:main:Received webhook for repository: test-org/test-repo
INFO:main:Generated CI/CD Pipeline:
INFO:main:name: CI/CD Pipeline
INFO:main:Pipeline saved to: /app/.github/workflows/ci-cd.yml
```

---

## System Architecture

### Components

```
┌─────────────────────────────────────────────────────┐
│  GitHub / Local Test              │  User           │
│  (Code Push with Diff)             │                │
└────────────────┬────────────────────────────────────┘
                 │ HTTP: POST /webhook/github
                 │ Payload: {repository, diff, commit_message}
                 ↓
┌─────────────────────────────────────────────────────┐
│              WEBHOOK SERVICE                         │
│  FastAPI | Port 8001 | 2 Replicas                  │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │ POST /webhook/github                           │ │
│  │  • Responds 200 OK immediately (< 100ms)      │ │
│  │  • Queues background async task                │ │
│  └────────────────────────────────────────────────┘ │
│                 │                                     │
│  ┌──────────────┴────────────────────────────────┐  │
│  │ Background Task: call_ai_async()              │  │
│  │  • Extracts diff + metadata                   │  │
│  │  • Calls AI service /generate-pipeline       │  │
│  │  • Retry logic: 3 attempts, exponential backoff │ │
│  │  • Timeout: 90 seconds                         │  │
│  │  • Auto-saves YAML to file on success          │  │
│  └────────────────┬─────────────────────────────┘   │
└────────────────────┼──────────────────────────────────┘
                     │ HTTP: POST /generate-pipeline
                     │ Payload: {diff, repository, commit_message}
                     ↓
┌─────────────────────────────────────────────────────┐
│              AI SERVICE                              │
│  FastAPI | Port 8000 | 1 Replica                   │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │ POST /generate-pipeline                        │ │
│  │  • Receives code diff + metadata               │ │
│  │  • Builds strict prompt (YAML-only output)    │ │
│  │  • Calls DeepSeek API                          │ │
│  │  • Sanitizes response (removes prose)          │ │
│  │  • Returns pure GitHub Actions YAML            │ │
│  └────────────────┬─────────────────────────────┘   │
└────────────────────┼──────────────────────────────────┘
                     │ HTTPS: /v1/chat/completions
                     │ Authorization: Bearer {DEEPSEEK_API_KEY}
                     ↓
┌─────────────────────────────────────────────────────┐
│              DEEPSEEK API                            │
│  https://api.deepseek.com/v1/chat/completions     │
│  • Analyzes code diff                              │
│  • Generates GitHub Actions YAML pipeline          │
│  • Response time: 15-30 seconds                    │
└─────────────────────────────────────────────────────┘
```

### Data Flow (Detailed)

```
TIME    0ms: GitHub sends webhook payload
            {
              "repository": {"full_name": "org/repo"},
              "head_commit": {"id": "abc123", "message": "Add feature"},
              "diff": "diff --git a/... (full code diff)"
            }

TIME   50ms: Webhook service receives request
            Logs: "Received webhook for repository: org/repo"

TIME   75ms: Webhook service extracts diff
            Logs: "Extracted diff (1250 chars) from repository"
            Queues background task
            Responds 200 OK to GitHub

TIME  100ms: GitHub receives 200 OK status
            Webhook delivery marked as successful

TIME  150ms: Background task starts processing
            Logs: "Processing webhook payload (attempt 1/4)"

TIME  200ms: Task calls AI service
            POST to http://ai-service:8000/generate-pipeline
            Payload: {
              "diff": "...",
              "repository": "org/repo",
              "commit_message": "Add feature"
            }

TIME 1000ms: AI service receives request
            Builds prompt with code diff
            Calls DeepSeek API with HTTPS

TIME 20000ms: DeepSeek API processes request
            Analyzes code changes
            Generates GitHub Actions YAML

TIME 21000ms: DeepSeek API responds with YAML
            AI service sanitizes response
            Removes any prose/explanations
            Keeps only pure YAML

TIME 21500ms: Webhook service receives YAML
            Logs: "Generated CI/CD Pipeline:"
            Logs: GitHub Actions YAML content
            Saves to .github/workflows/ci-cd.yml
            Logs: "Pipeline saved to: /app/.github/workflows/ci-cd.yml"

TIME 22000ms: Complete
            Ready for next webhook
```

---

## File Structure

```
dmd-cloud-project/
│
├── webhook_service/                ← Webhook receiver + AI coordinator
│   ├── main.py                      ├─ FastAPI app
│   ├── Dockerfile                   ├─ Container image
│   └── requirements.txt              └─ Dependencies
│
├── ai_service/                      ← AI pipeline generator
│   ├── main.py                      ├─ FastAPI app
│   ├── Dockerfile                   ├─ Container image
│   └── requirements.txt              └─ Dependencies
│
├── k8s/                             ← Kubernetes manifests
│   ├── webhook-deployment.yaml      ├─ Webhook service deployment
│   ├── ai-deployment.yaml           └─ AI service deployment
│
├── README.md                        ← This file
│
├── test-workflow.ps1                 ← Test script
│
├── ARCHITECTURE.md                  ← Detailed architecture (optional)
│
└── [Old guides - can be deleted after reading this README]
    ├── HOW_TO_USE_WORKFLOW.md       (covered in "Common Tasks" below)
    ├── EXPECTED_RESULTS_CHECKLIST.md
    ├── DATA_FLOW_EXAMPLES.md
    └── ... (other old docs)
```

### Essential Files Explained

| File | Purpose | Not Needed |
|------|---------|-----------|
| `webhook_service/main.py` | Receives webhooks, calls AI | ✅ Core |
| `ai_service/main.py` | Calls DeepSeek, returns YAML | ✅ Core |
| `k8s/*.yaml` | Kubernetes deployment configs | ✅ Core |
| `README.md` | This comprehensive guide | ✅ Core |
| `test-workflow.ps1` | Test script | ✅ Helpful |
| `ARCHITECTURE.md` | Deep technical details | ⚠️ Reference only |
| `HOW_TO_USE_WORKFLOW.md` | Old guide | ❌ Delete - covered here |
| `EXPECTED_RESULTS_CHECKLIST.md` | Old checklist | ❌ Delete |
| `DATA_FLOW_EXAMPLES.md` | Old examples | ❌ Delete |
| `FULL_WORKFLOW_GUIDE.md` | Old doc | ❌ Delete |

---

## Common Tasks

### 1. Integrate with Real GitHub Repository

**Setup:**
1. Go to your GitHub repo → **Settings → Webhooks** 
2. Click **Add webhook**
3. **Payload URL:** `https://your-domain.ngrok-free.dev/webhook/github`
4. **Content type:** `application/json`
5. **Events:** Select **Pushes**
6. **SSL verification:** Enable
7. Click **Add webhook**

**Trigger:**
```bash
git add .
git commit -m "Feature: add authentication module"
git push origin main
```

**Verify:**
- Check GitHub webhook delivery (green checkmark ✓ = success)
- Check `.github/workflows/ci-cd.yml` created in your repo
- Pipeline is ready to use!

### 2. Test Without GitHub (Local Testing)

**Run the test script:**
```powershell
powershell -File .\test-workflow.ps1
```

**Or manually:**
```powershell
# Start port-forward if not running
kubectl port-forward service/webhook-service 8001:8001 &

# Create test payload
$payload = @{
    repository = @{ full_name = "myorg/myrepo" }
    head_commit = @{ 
        id = "commit-hash-here"
        message = "Add new feature"
    }
    diff = @"
diff --git a/src/main.py b/src/main.py
new file mode 100644
index 0000000..abc1234
--- /dev/null
+++ b/src/main.py
@@ -0,0 +1,5 @@
+import os
+
+def main():
+    print("Hello")
+
"@
} | ConvertTo-Json -Depth 10

# Send webhook
Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
    -Method POST -Body $payload -ContentType "application/json"

# Wait for processing
Start-Sleep -Seconds 45

# Check logs
kubectl logs -l app=webhook-service --since=2m
```

### 3. View Generated Pipelines

**In Kubernetes pod (transient):**
```powershell
kubectl logs -l app=webhook-service --since=5m | Select-String "Generated CI/CD Pipeline" -Context 0,30
```

**In saved file (persistent):**
```powershell
# Pipeline is auto-saved inside pod at /app/.github/workflows/ci-cd.yml
# Copy from pod or just copy the logs
```

### 4. Customize the AI Prompt

Edit **[ai_service/main.py](ai_service/main.py)** around line 20:

```python
prompt = f"""
You are a CI/CD pipeline expert.

Task:
- Analyze the git diff below
- Generate a production-ready GitHub Actions workflow
- Output ONLY raw YAML (no markdown, no explanations)

Requirements:
- Use ubuntu-latest runners
- Include Python setup if python files detected
- Add linting, testing, and deployment stages
- Use best practices for security and caching

Git diff:

{data.get("diff")}
"""
```

Save, rebuild, and redeploy:
```powershell
minikube image build -t ai-service:custom ./ai_service
kubectl set image deployment/ai-service ai-service=ai-service:custom
kubectl rollout status deployment/ai-service
```

### 5. Change Output File Location

Edit **[k8s/webhook-deployment.yaml](k8s/webhook-deployment.yaml):**

```yaml
env:
  - name: PIPELINE_OUTPUT_PATH
    value: ".github/workflows/my-pipeline.yml"
  - name: AUTO_SAVE_PIPELINE
    value: "true"
```

Apply and restart:
```powershell
kubectl apply -f k8s/webhook-deployment.yaml
kubectl rollout restart deployment/webhook-service
```

### 6. Disable Auto-Save (Manual Save Only)

```yaml
env:
  - name: AUTO_SAVE_PIPELINE
    value: "false"
```

Then copy YAML from logs manually.

### 7. Increase Webhook Timeout (for slow networks)

Edit **[k8s/webhook-deployment.yaml](k8s/webhook-deployment.yaml):**

```yaml
env:
  - name: AI_SERVICE_TIMEOUT_SECONDS
    value: "120"  # Instead of 90
```

### 8. Scale Webhook Service for High Load

```powershell
kubectl scale deployment webhook-service --replicas=5
```

---

## Troubleshooting

### Issue: Pods won't start / CrashLoopBackOff

**Diagnose:**
```powershell
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
```

**Common causes:**
- DeepSeek API key secret not created
- Image not found
- Port conflict

**Fix:**
```powershell
# Recreate secret
kubectl delete secret ai-service-secrets
kubectl create secret generic ai-service-secrets `
  --from-literal=DEEPSEEK_API_KEY="sk-xxxx"

# Rebuild images
minikube image build -t webhook-service:latest ./webhook_service
minikube image build -t ai-service:latest ./ai_service

# Restart
kubectl rollout restart deployment/webhook-service
kubectl rollout restart deployment/ai-service
```

### Issue: Webhook returns 500 error

**Check logs:**
```powershell
kubectl logs -l app=webhook-service --tail=50
```

**Common:**
- AI service unreachable
- DeepSeek API key invalid
- Network timeout

**Fix:**
```powershell
# Test AI service health
kubectl exec -it <webhook-pod> -- curl http://ai-service:8000/health

# Test DeepSeek connectivity from pod
kubectl exec -it <ai-pod> -- python -c "import requests; print(requests.get('https://api.deepseek.com'))"
```

### Issue: AI service times out (no response)

**Increase timeout:**
```yaml
AI_SERVICE_TIMEOUT_SECONDS: "180"
DEEPSEEK_TIMEOUT_SECONDS: "90"
```

**Check DeepSeek status:**
```powershell
# Verify API key works
$headers = @{Authorization = "Bearer sk-your-key"}
Invoke-WebRequest -Uri "https://api.deepseek.com/v1/chat/completions" `
    -Headers $headers -Method Post -Body @{messages=@{role="user";content="test"}} -ContentType "application/json"
```

### Issue: Pipeline not saved to file

**Verify ENV variables:**
```powershell
kubectl get deployment webhook-service -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AUTO_SAVE_PIPELINE")]}'
```

**Check pod filesystem:**
```powershell
kubectl exec <pod> -- ls -la .github/workflows/
```

**Container has no persistent storage**, so files inside pod (`/app/.github/workflows/ci-cd.yml`) are temporary. For persistence, mount a volume or use a Git commit strategy.

---

## Performance Baseline

| Stage | Duration | Notes |
|-------|----------|-------|
| Webhook response | <100ms | Immediate 200 OK |
| Background processing start | ~50ms | Queued task |
| AI service call initiation | ~200ms | Network hop |
| DeepSeek API round-trip | 15-30s | LLM inference |
| YAML sanitization | ~100ms | Parsing/regex |
| File write | <500ms | Local I/O |
| **Total (webhook to save)** | **15-30s** | User wait time |

---

## Environment Configuration

### Webhook Service (k8s/webhook-deployment.yaml)

```yaml
env:
  # URL to AI service
  - name: AI_SERVICE_URL
    value: "http://ai-service:8000"
  
  # How long to wait for AI service reply
  - name: AI_SERVICE_TIMEOUT_SECONDS
    value: "90"
  
  # YAML auto-save feature
  - name: AUTO_SAVE_PIPELINE
    value: "true"
  
  # Where to save generated YAML
  - name: PIPELINE_OUTPUT_PATH
    value: ".github/workflows/ci-cd.yml"
```

### AI Service (k8s/ai-deployment.yaml)

```yaml
env:
  # DeepSeek API authentication (from secret)
  - name: DEEPSEEK_API_KEY
    valueFrom:
      secretKeyRef:
        name: ai-service-secrets
        key: DEEPSEEK_API_KEY
  
  # DeepSeek API timeout
  - name: DEEPSEEK_TIMEOUT_SECONDS
    value: "60"
```

---

## API Reference

### Webhook Service Endpoints

#### POST /webhook/github
Receives GitHub webhook payload and queues pipeline generation.

**Request:**
```json
{
  "repository": {
    "full_name": "org/repo"
  },
  "head_commit": {
    "id": "abc123",
    "message": "Commit message"
  },
  "diff": "diff --git a/... (full diff)"
}
```

**Response (always 200):**
```json
{
  "status": "received",
  "message": "Webhook received and queued for pipeline generation"
}
```

#### GET /health
Kubernetes liveness/readiness probe.

**Response:**
```json
{
  "status": "healthy",
  "ai_service": "healthy"
}
```

### AI Service Endpoints

#### POST /generate-pipeline
Generates GitHub Actions YAML from code diff.

**Request:**
```json
{
  "diff": "diff --git a/...",
  "repository": "org/repo",
  "commit_message": "Commit message"
}
```

**Response:**
```json
{
  "id": "chatcmpl-xxx",
  "choices": [
    {
      "message": {
        "content": "name: CI/CD Pipeline\non:\n  push:\njobs:\n..."
      }
    }
  ]
}
```

#### GET /health
Health check.

**Response:**
```json
{
  "status": "ok"
}
```

---

## Deployment Stages

### Stage 1: Prerequisites ✓
- [ ] Minikube running (test with `minikube status`)
- [ ] kubectl installed (`kubectl version`)
- [ ] Docker available (`docker ps`)
- [ ] DeepSeek API key obtained

### Stage 2: Setup ✓
- [ ] Kubernetes secret created
- [ ] Docker images built
- [ ] K8s deployments applied
- [ ] All pods running (2 webhook + 1 AI)

### Stage 3: Verification ✓
- [ ] Webhook service responds to /health
- [ ] AI service responds to /health
- [ ] Port-forward works
- [ ] Local test passes

### Stage 4: Production (Optional)
- [ ] ngrok tunnel configured
- [ ] GitHub webhook set up
- [ ] Real push triggers pipeline
- [ ] Pipeline YAML appears in repo

---

## Clean Up / Reset

```powershell
# Delete everything
kubectl delete deployment webhook-service ai-service
kubectl delete service webhook-service ai-service
kubectl delete secret ai-service-secrets

# Rebuild from scratch
minikube image rm webhook-service:latest ai-service:latest

# Or fully reset minikube
minikube delete
minikube start
```

---

## Support

**Check system health:**
```powershell
kubectl get all
kubectl describe nodes
kubectl top pods
```

**View all logs:**
```powershell
kubectl logs -l app=webhook-service -l app=ai-service --all-containers=true --tail=100
```

**Get events:**
```powershell
kubectl get events --sort-by='.lastTimestamp'
```

**Kubectl cheat sheet:**
```powershell
kubectl get pods                           # List all pods
kubectl describe pod <name>                # Pod details
kubectl logs <pod>                         # Pod logs
kubectl exec -it <pod> -- /bin/bash        # Shell into pod
kubectl port-forward <pod> 8000:8000       # Port mapping
kubectl scale deployment <name> --replicas=3  # Scale
kubectl rollout restart deployment/<name>  # Restart
```

---

## Security Best Practices

1. **Never commit API keys** to git
2. **Use Kubernetes Secrets** for sensitive data
3. **Restrict webhook** to specific IPs if possible
4. **Use HTTPS** for ngrok/production webhooks
5. **Enable webhook SSL verification** in GitHub settings
6. **Monitor logs** for suspicious activity
7. **Rotate API keys** periodically
8. **Use network policies** to restrict traffic between pods

---

**Project Status:** Production Ready ✅  
**Last Updated:** March 2026  
**Version:** 1.0


1. Start Minikube:
   ```bash
   minikube start
   ```

2. Build images in Minikube Docker environment:
   ```bash
   minikube image build -t ai-service:latest ./ai_service
   minikube image build -t webhook-service:latest ./webhook_service
   ```

3. Create secret (do not commit real keys):
   ```bash
   kubectl apply -f k8s/ai-service-secret.template.yaml
   ```

4. Deploy workloads:
   ```bash
   kubectl apply -f k8s/
   ```

5. Open the webhook service:
   ```bash
   minikube service webhook-service
   ```

## Azure Deployment

1. Install Terraform and Azure CLI
2. Authenticate:
   ```bash
   az login
   ```
3. Provision AKS:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

## Notes

- Keep `ai-service` as `ClusterIP` when only internal service-to-service traffic is needed.
- Change `Service` type to `LoadBalancer` or use Ingress if you need controlled external access.
- **Timeout Configuration**: DeepSeek API responses can take 40-60 seconds. The defaults are:
  - `AI_SERVICE_TIMEOUT_SECONDS=75` (webhook waiting for AI service)
  - `DEEPSEEK_TIMEOUT_SECONDS=60` (AI service waiting for DeepSeek API)
  - Adjust these if you experience timeout errors or if the external API is slower/faster.
- Use `test-webhook.json` for local testing with curl or Postman.
- flow
        - GitHub push
           ↓
        Webhook receives
           ↓
        Returns 200 immediately
           ↓
        Calls AI async
           ↓
        AI generates pipeline