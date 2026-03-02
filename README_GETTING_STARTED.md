# 📖 Getting Started: Enable AI Pipeline Generation

## Quick Overview

Your system is already set up to:
1. ✅ Receive GitHub webhooks
2. ✅ Respond instantly (< 100ms)
3. ✅ Process code diffs asynchronously
4. ❌ **Generate CI/CD pipelines using AI** ← This is what we need to finish!

This guide walks you through the final setup to get AI-generated pipelines working.

---

## 🎯 The Goal

When you push code to GitHub:
```
GitHub Push Event
        ↓
    Webhook Service receives
        ↓
  Returns 200 OK immediately ⚡
        ↓
  AI analyzes your code diff
        ↓
  DeepSeek generates GitHub Actions YAML
        ↓
  Pipeline logged and ready to use ✅
```

---

## 🚀 Get Started in 4 Steps

### Step 1️⃣: Get DeepSeek API Key (2 minutes)

1. Go to https://platform.deepseek.com/
2. Create an account or login
3. Navigate to API Keys
4. Click "Create New Key"
5. Copy your key (starts with `sk-`)
6. **Save it somewhere safe** (you'll need it in Step 2)

**✅ You now have:** DeepSeek API Key

---

### Step 2️⃣: Create Kubernetes Secret (1 minute)

Create a new file: `k8s/ai-service-secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-service-secrets
  namespace: default
type: Opaque
stringData:
  DEEPSEEK_API_KEY: "sk-YOUR_API_KEY_FROM_STEP_1"
```

Then run:
```bash
kubectl apply -f k8s/ai-service-secret.yaml
```

Verify it worked:
```bash
kubectl get secrets
# You should see: ai-service-secrets
```

**✅ You now have:** Secret stored in Kubernetes

---

### Step 3️⃣: Rebuild Webhook Service (3 minutes)

The webhook service code was already updated to call the AI service's `/generate-pipeline` endpoint. Build the image:

**Option A: Direct Docker**
```bash
docker build -t webhook-service:latest ./webhook_service
```

**Option B: Using Minikube**
```bash
minikube image build -t webhook-service:latest ./webhook_service
```

Then restart the service:
```bash
kubectl rollout restart deployment/webhook-service
```

Wait for pods to be ready:
```bash
kubectl get pods -l app=webhook-service
# Should show: 1/1 Running for both pods
```

**✅ You now have:** Updated webhook service running

---

### Step 4️⃣: Restart AI Service (1 minute)

```bash
kubectl rollout restart deployment/ai-service
```

Verify:
```bash
kubectl get pods -l app=ai-service
# Should show: 1/1 Running
```

**✅ You now have:** AI service ready with secret configured

---

## ✅ Test It Works (5 minutes)

### Test 1: Send a Webhook

```bash
$payload = Get-Content test-webhook.json -Raw

Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
  -Method POST `
  -ContentType "application/json" `
  -Body $payload
```

**Expected response:**
```
StatusCode : 200
Content    : {
  "status": "received",
  "message": "Webhook received and queued for pipeline generation"
}
```

✅ **Webhook accepted!**

---

### Test 2: Watch Logs

Open a **new terminal** and run:
```bash
kubectl logs -f -l app=webhook-service --all-containers=true
```

**Watch for these messages (in order):**

1. (Immediate)
```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
```

2. (1-2 seconds)
```
INFO:main:Processing webhook payload (attempt 1/4)
INFO:main:Extracted diff (547 chars) from repository: taoufikmohamed/dmd-cloud
```

3. (2-3 seconds)
```
INFO:main:Calling AI service: POST http://ai-service:8000/generate-pipeline
```

4. (10-30 seconds later - this is the AI thinking!)
```
INFO:main:Successfully generated pipeline from AI service
INFO:main:Generated CI/CD Pipeline:
name: Python CI/CD Pipeline
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
      ...
```

✅ **Success! Pipeline was generated!**

---

## 📚 Documentation Guide

I've created 7 comprehensive guides for you:

| Guide | Purpose | Read When |
|-------|---------|-----------|
| **ACTION_PLAN.md** | Step-by-step checklist | You're ready to implement |
| **QUICK_START_PIPELINE.md** | 4-step fast setup | Quick reference |
| **FULL_WORKFLOW_GUIDE.md** | Complete explanation | You want to understand the flow |
| **DATA_FLOW_EXAMPLES.md** | Input/output examples | You want to see actual data |
| **SYSTEM_ARCHITECTURE.md** | Diagrams and architecture | You want the big picture |
| **EXPECTED_RESULTS_CHECKLIST.md** | What to look for | You need detailed success criteria |
| **TESTING_WITH_NGROK.md** | GitHub integration | You're ready to test with GitHub |

---

## 🎯 What Happens Next

After you complete the 4 setup steps:

1. **Local Testing (5 min)**
   - Send test webhook
   - Watch logs
   - See "Generated CI/CD Pipeline:" message

2. **Optional: Test with GitHub (10 min)**
   - Start ngrok
   - Configure GitHub webhook
   - Push real code
   - Watch it generate pipeline!

3. **Optional: Save Generated Pipelines (future)**
   - Store pipelines in a database
   - Auto-commit them to repo
   - Use them in actual CI/CD

---

## 🔍 Verify Each Step

### After Step 1: ✅ API Key
```
You have: sk-xxxxxxxxxxxxxxxxxx
Save it: For Step 2
```

### After Step 2: ✅ Secret Created
```bash
kubectl get secrets | grep ai-service
# Output: ai-service-secrets   Opaque   1      5s
```

### After Step 3: ✅ Webhook Rebuilt
```bash
kubectl get pods -l app=webhook-service
# Output: 
# webhook-service-xxx   1/1   Running   0   1m
# webhook-service-yyy   1/1   Running   0   1m
```

### After Step 4: ✅ AI Service Ready
```bash
kubectl get pods -l app=ai-service
# Output:
# ai-service-xxx   1/1   Running   0   1m
```

### After Test 1: ✅ Webhook Responds
```
Status Code: 200
Message: "Webhook received and queued for pipeline generation"
```

### After Test 2: ✅ Pipeline Generated
Look for in logs:
```
INFO:main:Generated CI/CD Pipeline:
name: ...
```

---

## 💡 Key Insights

### Why You Return Instantly

GitHub gives you **30 seconds max** before timing out. If you wait for AI (10-30 seconds), you'll timeout. Solution:
- Return 200 OK immediately (< 100ms) ✅
- Process pipeline in background (10-30s) ✅
- GitHub never knows it took time ✅

### Why You Use `/generate-pipeline` Endpoint

The webhook could just POST to root, but that's ambiguous:
- ❌ AI service doesn't know what to do
- ❌ Could be for training, testing, or generating

By calling `/generate-pipeline` explicitly:
- ✅ AI service knows: "generate a pipeline"
- ✅ Same endpoint can be reused for other tasks
- ✅ Clear intent in the code

### Why Logs Show the Pipeline

The generated pipeline is logged so:
- You can see what AI generated
- You can review it for quality
- Later, you could save/use it automatically
- Debugging is easier (full visibility)

---

## 🚀 After Setup Works

Once you see "Generated CI/CD Pipeline:" in logs, you can:

1. **Save pipelines to git:**
   - Auto-commit generated pipelines
   - Track AI decisions over time

2. **Validate pipelines:**
   - Run syntax checks
   - Validate YAML format
   - Reject if quality issues

3. **Use in real CI/CD:**
   - Automatically create GitHub Actions workflow
   - Run the generated pipeline on your code
   - Get feedback automatically

4. **Improve AI responses:**
   - Track which pipelines work best
   - Fine-tune AI prompts
   - Customize for your tech stack

---

## ⏱️ Time Investment

```
Setup:           ~15 minutes
  - API key      2 min
  - Secret       1 min
  - Build image  3 min
  - Restart      2 min
  - Wait         7 min

Local Testing:   ~5 minutes
  - Send webhook 1 min
  - Watch logs   4 min

Optional GitHub: ~10 minutes
  - Setup ngrok  2 min
  - Configure    3 min
  - Test push    5 min

TOTAL: 20-30 minutes to fully working system
```

---

## ❓ Common Questions

### Q: Do I have to pay for DeepSeek API?
**A:** Yes, but it's very cheap (~$0.14 per 1M tokens). A typical code diff is ~1000 tokens, so very affordable.

### Q: Can I use a different AI API?
**A:** Yes! Modify the AI service code to call OpenAI, Anthropic, etc. instead of DeepSeek.

### Q: What if the pipeline generation fails?
**A:** The webhook still succeeds (200 OK to GitHub). Background task retries 3 times. If still fails, you'll see errors in logs.

### Q: Where do the generated pipelines get saved?
**A:** Currently, they're logged to Kubernetes logs. You could extend the system to save them to git, a database, or S3.

### Q: Can I customize what the AI generates?
**A:** Yes! Edit the prompt in `ai_service/main.py`. You can customize for your language, framework, requirements, etc.

---

## 🎬 Real Example

Here's what a **real** generated pipeline might look like for a Python project:

```yaml
name: Python Testing and Deployment
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.9', '3.10', '3.11']
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python-version }}
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest flake8 black
      - name: Lint with flake8
        run: flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
      - name: Format check with black
        run: black --check .
      - name: Run tests
        run: pytest tests/ -v --cov=. --cov-report=xml
      - name: Upload coverage
        uses: codecov/codecov-action@v3
  deploy:
    needs: lint-and-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to production
        run: |
          echo "Deploying to production..."
          # Your deployment commands here
```

That's what AI generates from your code diff! 🤖✨

---

## 🎉 You're Ready!

Everything is set up. All you need to do:

1. ✅ Follow the 4 setup steps above
2. ✅ Run the tests
3. ✅ Watch for "Generated CI/CD Pipeline:" in logs
4. ✅ Enjoy automated pipeline generation! 🚀

**Start with Step 1 now!** ⬆️

---

## 📞 If Something Goes Wrong

Check these guides in order:
1. **QUICK_START_PIPELINE.md** - Most common issues
2. **EXPECTED_RESULTS_CHECKLIST.md** - Verify each step
3. **DATA_FLOW_EXAMPLES.md** - Understand the data
4. **FULL_WORKFLOW_GUIDE.md** - Complete troubleshooting

---

**Good luck! You've got this! 💪🚀**
