# 🎯 Complete Action Plan: Enable Full Workflow

## What You Have Now vs What You Want

### Current State ❌
```
GitHub → Webhook Service → Returns 200 ✓
                       ✓ but...
                       Processing happens in background
                       AI service called (generic)
                       No actual pipeline generated
```

### Target State ✅
```
GitHub → Webhook Service → Returns 200 instantly ⚡
                       ↓
                    Extract Diff
                       ↓
                    Call AI Service /generate-pipeline
                       ↓
                    DeepSeek generates YAML pipeline
                       ↓
                    Logs show generated pipeline
```

---

## Your To-Do List (In Order)

### 🎬 Phase 1: Setup (Today)

#### Task 1: Get DeepSeek API Key ⏱️ 2 min
- [ ] Go to https://platform.deepseek.com/
- [ ] Sign up / Login
- [ ] Create API key
- [ ] Copy key (format: `sk-xxxxxxxxxxxxx`)
- [ ] Keep it safe (don't commit to git!)

#### Task 2: Create Kubernetes Secret ⏱️ 1 min
- [ ] Create file `k8s/ai-service-secret.yaml`:
  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: ai-service-secrets
  type: Opaque
  stringData:
    DEEPSEEK_API_KEY: "sk-YOUR_KEY_FROM_STEP_1"
  ```
- [ ] Run: `kubectl apply -f k8s/ai-service-secret.yaml`
- [ ] Verify: `kubectl get secrets | grep ai-service`

#### Task 3: Rebuild Webhook Service ⏱️ 3 min
The code was already updated in `webhook_service/main.py`. Build it:

```bash
# Option 1: Direct Docker
docker build -t webhook-service:latest ./webhook_service

# Option 2: Using minikube
minikube image build -t webhook-service:latest ./webhook_service
```

- [ ] Build completed successfully
- [ ] Run: `kubectl rollout restart deployment/webhook-service`
- [ ] Wait: `kubectl get pods -l app=webhook-service` shows `1/1 Running` (both pods)

#### Task 4: Restart AI Service ⏱️ 1 min
- [ ] Run: `kubectl rollout restart deployment/ai-service`
- [ ] Verify: `kubectl get pods -l app=ai-service` shows `1/1 Running`

---

### 🧪 Phase 2: Test Locally (10 min)

#### Test 1: Send Webhook
```bash
$payload = Get-Content test-webhook.json -Raw
Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
  -Method POST `
  -ContentType "application/json" `
  -Body $payload
```

**Expected response:**
```json
{
  "status": "received",
  "message": "Webhook received and queued for pipeline generation"
}
```

- [ ] Got 200 response ✅

#### Test 2: Watch Logs (New Terminal)
```bash
kubectl logs -f -l app=webhook-service --all-containers=true
```

**Watch for these in order:**

1. `Received webhook for repository: taoufikmohamed/dmd-cloud`
   - [ ] Saw this ✓

2. `Processing webhook payload (attempt 1/4)`
   - [ ] Saw this ✓

3. `Extracted diff (...) from repository`
   - [ ] Saw this ✓

4. `Calling AI service: POST http://ai-service:8000/generate-pipeline`
   - [ ] Saw this ✓

5. `Successfully generated pipeline from AI service`
   - [ ] Saw this ✓

6. `Generated CI/CD Pipeline:` (followed by YAML)
   - [ ] Saw this ✓ **← THIS IS SUCCESS!**

---

### 🌐 Phase 3: Test with GitHub (if using ngrok)

#### Setup ngrok
- [ ] Run in terminal: `ngrok http 8001`
- [ ] Copy ngrok URL: `https://xxx-xxx.ngrok-free.dev`

#### Configure GitHub
1. Go to: https://github.com/taoufikmohamed/dmd-cloud/settings/hooks
2. Add webhook:
   - Payload URL: `https://YOUR_NGROK_URL/webhook/github`
   - Content type: `application/json`
   - Events: Push events
   - Active: ✓ Yes

- [ ] Webhook added ✓

#### Test with Real Push
```bash
git add .
git commit -m "Test webhook"
git push origin master
```

- [ ] Push completed ✓
- [ ] Check GitHub webhook: Recent Deliveries shows ✅ success ✓
- [ ] Check logs: See "Generated CI/CD Pipeline:" ✓

---

## 📚 Reference Documents Created

I created several guides for you:

| Document | Purpose | When to Use |
|----------|---------|------------|
| `QUICK_START_PIPELINE.md` | 4-step setup guide | Get it running fast |
| `FULL_WORKFLOW_GUIDE.md` | Detailed explanation | Understand the flow |
| `DATA_FLOW_EXAMPLES.md` | Input/output examples | See actual data |
| `EXPECTED_RESULTS_CHECKLIST.md` | What to look for | Verify each step |
| `TESTING_WITH_NGROK.md` | GitHub integration | Test with real webhooks |

**Start with:** `QUICK_START_PIPELINE.md` ← Do this first!

---

## ✅ How to Know It's Working

### Minimum (Local Test Only)
```
✅ Send webhook
✅ Get 200 response immediately
✅ Logs show "Generated CI/CD Pipeline:"
✅ YAML content appears in logs
```

### Full (With GitHub)
```
All of above, PLUS:
✅ ngrok tunnel active
✅ GitHub webhook configured
✅ Real push triggers webhook
✅ GitHub shows ✅ green checkmark
✅ Logs show pipeline generation
```

---

## 🚨 If Something's Wrong

### Problem: "404 Not Found" errors
**Cause:** Old webhook code is running (hasn't been rebuilt)  
**Fix:** Rebuild docker image (Task 3)

### Problem: "DEEPSEEK_API_KEY is not configured"
**Cause:** Secret wasn't created  
**Fix:** Create secret file and run `kubectl apply` (Task 2)

### Problem: No "Generated CI/CD Pipeline" in logs
**Cause:** Could be several things (see below)

**Diagnostics:**
1. Check AI service logs:
   ```bash
   kubectl logs -l app=ai-service | tail -20
   ```
   Look for DeepSeek API errors

2. Check secret exists:
   ```bash
   kubectl get secrets ai-service-secrets
   ```

3. Verify API key is valid:
   - Go to https://platform.deepseek.com/
   - Check your API key hasn't been disabled

4. Test AI service directly:
   ```bash
   kubectl exec -it <AI_POD> -- curl http://localhost:8000/health
   ```

---

## 🎓 Key Concepts

#### Why Async?
- GitHub times out after 30 seconds
- AI generation takes 10-30 seconds
- Solution: Return immediately (100ms), process in background

#### Why `/generate-pipeline` endpoint?
- Generic POST to root wouldn't work
- AI service needs to know: "generate a pipeline from this diff"
- Explicit endpoint makes intent clear

#### Why logs show the pipeline?
- Pipeline is generated and logged
- Gives you visibility into AI decisions
- You could save/use this pipeline automatically later

---

## 🎬 Expected Timeline

**Total time to working system:**

```
Phase 1 Setup:     ~10 minutes
  - Get API key     2 min
  - Create secret   1 min
  - Rebuild image   3 min
  - Restart pods    2 min
  - Wait for pods   2 min

Phase 2 Local Test: ~5 minutes
  - Send webhook    1 min
  - Watch logs      1 min
  - Verify output   3 min

Phase 3 GitHub:     ~5 minutes
  - Setup ngrok     1 min
  - Configure GH    2 min
  - Test push       2 min

TOTAL: ~20 minutes to fully working AI pipeline system
```

---

## 💪 You've Got This!

Everything is set up for you:
- ✅ Code updated (webhook calls `/generate-pipeline`)
- ✅ Kubernetes configs ready (deployments, services)
- ✅ Documentation complete (4 detailed guides)
- ✅ Testing scripts included

**All you need to do:**
1. Get API key (2 min)
2. Create secret (1 min)
3. Rebuild webhook (3 min)
4. Test locally (5 min)

**That's it!**

---

## 🚀 Next Step

→ Open `QUICK_START_PIPELINE.md` and follow the 4 steps

---

## ❓ Questions?

Look at the guides:
- **How does it work?** → `FULL_WORKFLOW_GUIDE.md`
- **What data flows where?** → `DATA_FLOW_EXAMPLES.md`
- **What should I see in logs?** → `EXPECTED_RESULTS_CHECKLIST.md`
- **How do I test with GitHub?** → `TESTING_WITH_NGROK.md`

---

**You're 20 minutes away from an AI-powered CI/CD pipeline generator!** 🤖✨
