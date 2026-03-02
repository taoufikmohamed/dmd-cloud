# ✅ What to Check: Webhook Workflow Verification

## Overview

This guide shows you **exactly what to look for** to confirm your webhook workflow is working correctly at each stage.

---

## 🎯 Complete Workflow Check List

### Stage 1: Local Testing (Before GitHub)
### Stage 2: ngrok Testing (Public URL)
### Stage 3: GitHub Integration (Real Webhooks)
### Stage 4: Production Monitoring

---

---

## 📋 STAGE 1: Local Testing

### Test 1A: Service is Running
**Command:**
```powershell
kubectl get pods -l app=webhook-service
```

**✅ What to Look For:**
```
NAME                                   READY   STATUS    RESTARTS   AGE
webhook-service-598877ff44-sqqhh       1/1     Running   0          26m
webhook-service-598877ff44-wjztq       1/1     Running   0          26m
```

**SUCCESS CRITERIA:**
- [ ] At least 2 pods showing `1/1 Running`
- [ ] All pods have status `Running` (NOT CrashLoopBackOff, Pending, or Failed)
- [ ] READY column shows `1/1` (pod is ready to receive traffic)

**❌ If Failed:**
```
webhook-service-598877ff44-sqqhh       0/1     CrashLoopBackOff   5          5m
```
→ Check logs: `kubectl logs <POD_NAME>`

---

### Test 1B: Health Endpoint
**Command:**
```powershell
Invoke-WebRequest -Uri "http://localhost:8001/health" -UseBasicParsing
```

**✅ What to Look For:**
```
StatusCode        : 200
StatusDescription : OK

{
  "status": "healthy",
  "ai_service": "healthy"
}
```

**SUCCESS CRITERIA:**
- [ ] StatusCode = `200` (not 404, 500, or connection refused)
- [ ] Response contains `"status": "healthy"`
- [ ] AI service shows as healthy (or check your AI service)

**Response Time:** Should be **< 50ms**

**❌ If Failed:**
```
Invoke-WebRequest: Unable to connect to the remote server
```
→ Make sure port-forward is running: `kubectl port-forward service/webhook-service 8001:8001`

---

### Test 1C: Webhook POST Request
**Command:**
```powershell
$payload = Get-Content test-webhook.json -Raw

$response = Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
  -Method POST `
  -ContentType "application/json" `
  -Body $payload `
  -UseBasicParsing

Write-Host "Status: $($response.StatusCode)"
Write-Host "Response: $($response.Content)"
```

**✅ What to Look For:**
```
Status: 200

{
  "status": "received",
  "message": "Webhook received and queued for processing"
}
```

**SUCCESS CRITERIA:**
- [ ] StatusCode = `200` (GitHub expects this)
- [ ] Response includes `"status": "received"`
- [ ] Message says "queued for processing"
- [ ] Response time < **100ms** ⚡ (CRITICAL - must be fast)

**The Response Time is Critical:**
```
⚡ < 100ms  → Perfect (webhook processes instantly)
⚡ 100-500ms → Good (still fast)
⏱️ 500ms-1s  → Acceptable (still under GitHub's 30s limit)
🐢 > 1s     → Too slow (maybe processing is blocking)
```

**❌ If Failed:**
```
Status: 404 Not Found
```
→ Check: `kubectl logs -l app=webhook-service`

---

### Test 1D: Check Logs for Processing
**Command:**
```powershell
kubectl logs -l app=webhook-service --tail=20 --all-containers=true
```

**✅ What to Look For:**

#### Best Case (AI service working):
```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Processing webhook payload (attempt 1/4)
INFO:httpx:HTTP Request: POST http://ai-service:8000 "HTTP/1.1 200 OK"
INFO:main:Successfully sent payload to AI service: 200
```

#### Good Case (AI service slow/fails but retrying):
```
INFO:main:Processing webhook payload (attempt 1/4)
INFO:httpx:HTTP Request: POST http://ai-service:8000 "HTTP/1.1 404 Not Found"
ERROR:main:Error calling AI service: HTTPStatusError...
INFO:main:Retrying in 1 seconds...
INFO:main:Processing webhook payload (attempt 2/4)
INFO:httpx:HTTP Request: POST http://ai-service:8000 "HTTP/1.1 200 OK"
INFO:main:Successfully sent payload to AI service: 200
```

**SUCCESS CRITERIA:**
- [ ] Log shows "Processing webhook payload"
- [ ] Either:
  - [ ] Shows "Successfully sent payload" (AI service responded)
  - OR [ ] Shows "Retrying" (auto-retry is working)
- [ ] No CRITICAL or FATAL errors

**Key Log Messages to See:**
```
✅ "Received webhook for repository"
✅ "Processing webhook payload"
✅ "HTTP Request: POST"
✅ Either "Successfully sent" OR "Retrying"
```

**❌ What You DON'T Want to See:**
```
❌ CRITICAL ERROR
❌ Traceback (Python error)
❌ 500 Internal Server Error
```

---

---

## 🌐 STAGE 2: ngrok Testing (Public URL)

### Test 2A: Start ngrok Tunnel
**Command:**
```powershell
ngrok http 8001
```

**✅ What to Look For:**
```
Session Status                online
Session Expires               1 hour 59 minutes
Version                       X.XX.X
Region                        United States (us)
Connections                   txn: 0 | evt: 0
Forwarding                    http://abc123defg45-xyz.ngrok-free.dev -> http://localhost:8001
Forwarding                    https://abc123defg45-xyz.ngrok-free.dev -> http://localhost:8001
```

**SUCCESS CRITERIA:**
- [ ] Status shows "online"
- [ ] See "Forwarding" with HTTPS URL (https://...ngrok-free.dev)
- [ ] URL is active and can be used immediately

**✅ Copy This URL:**
```
https://abc123defg45-xyz.ngrok-free.dev
```

**❌ If Failed:**
```
Error: Failed to connect
ERR_NGROK_8012
```
→ Make sure port-forward is running: `kubectl port-forward service/webhook-service 8001:8001`

---

### Test 2B: Test ngrok URL
**Command:**
```powershell
$NgrokUrl = "https://abc123defg45-xyz.ngrok-free.dev"

Invoke-WebRequest -Uri "$NgrokUrl/webhook/github" `
  -Method POST `
  -ContentType "application/json" `
  -Body (Get-Content test-webhook.json -Raw)
```

**✅ What to Look For:**
```
StatusCode        : 200
StatusDescription : OK

{
  "status": "received",
  "message": "Webhook received and queued for processing"
}
```

**SUCCESS CRITERIA:**
- [ ] Status Code = `200` (same as local test)
- [ ] Response is identical to local test
- [ ] Response time < **100ms**

**This proves:** ngrok tunnel is working and can forward traffic to your webhook.

---

### Test 2C: Check ngrok Dashboard
**Open:** http://localhost:4040

**✅ What to Look For:**

#### Main Dashboard Shows:
```
POST /webhook/github

Response Code: 200
Response Time: 23ms
```

#### Click on Request to See Details:
```
Method: POST
Host: abc123defg45-xyz.ngrok-free.dev
Path: /webhook/github
Status: 200
Size: 1.2 MB

Request Headers:
  Content-Type: application/json

Response Headers:
  Content-Type: application/json

Response Body:
{
  "status": "received",
  "message": "Webhook received and queued for processing"
}
```

**SUCCESS CRITERIA:**
- [ ] Shows POST request to `/webhook/github`
- [ ] Response Status = `200`
- [ ] Request body matches your test payload
- [ ] Response body shows "received"

**This confirms:** Traffic is flowing through ngrok correctly.

---

---

## 🐙 STAGE 3: GitHub Integration

### Test 3A: Configure GitHub Webhook
**Go to:** https://github.com/taoufikmohamed/dmd-cloud/settings/hooks

**✅ What to Look For:**

After clicking "Add webhook", you should see:
```
Webhooks
├── Payload URL: https://abc123defg45-xyz.ngrok-free.dev/webhook/github
├── Content type: application/json
├── Events: Just the push event ✓
└── Active: ✓ (checked)
```

**SUCCESS CRITERIA:**
- [ ] Webhook is listed in settings
- [ ] Payload URL matches your ngrok URL
- [ ] Content type = `application/json`
- [ ] Active checkbox is checked
- [ ] No error messages

---

### Test 3B: Test GitHub Webhook (Redeliver Method)

**Steps:**
1. Go to webhook settings (same page)
2. Click on the webhook
3. Scroll down to "Recent Deliveries"
4. Click the 🔄 (refresh) button on any delivery
5. GitHub will redeliver the webhook

**✅ What to Look For:**

#### In GitHub UI:
```
Recent Deliveries
├── ... a few seconds ago
│   ├── ID: 12345678910
│   ├── Status: ✅ (green checkmark)
│   └── Duration: 0.5s
│
└── ... (other past deliveries)
```

**Click on the delivery to see details:**
```
Request
  Method: POST
  URL: https://abc123defg45-xyz.ngrok-free.dev/webhook/github
  Status: 200
  
Response
  Status: 200
  Body: {
    "status": "received",
    "message": "Webhook received and queued for processing"
  }
```

**SUCCESS CRITERIA:**
- [ ] Status shows ✅ (green checkmark)
- [ ] Status code = `200`
- [ ] Duration is fast (< 1 second)
- [ ] No "timeout" or "connection refused" messages
- [ ] Response body shows "received"

**❌ If You See:**
```
Status: ❌ (red X)
Message: "Couldn't deliver this payload"
```
→ Check:
  1. Is ngrok still running?
  2. Is port-forward still active?
  3. Are webhook pods running?
  4. Check logs: `kubectl logs -l app=webhook-service`

---

### Test 3C: Real Push Event
**Steps:**
1. Make a commit and push:
   ```bash
   git add .
   git commit -m "Testing webhook"
   git push origin master
   ```
2. Immediately check GitHub webhook settings
3. Go to "Recent Deliveries" tab
4. You should see a new delivery within seconds

**✅ What to Look For:**
```
Recent Deliveries (newest first)
├── ... right now
│   ├── ID: 9876543210
│   ├── Status: ✅ (green checkmark)
│   └── Duration: 0.3s
└── ... (older deliveries)
```

**SUCCESS CRITERIA:**
- [ ] New delivery appears within 5 seconds of push
- [ ] Status = ✅ (green checkmark)
- [ ] Status Code = `200`
- [ ] Only one delivery for your commit (no duplicates)

**Click on delivery to see:**
```
Request
  URL includes: repository name, branch, commit SHA
  Status: 200
```

**This proves:** GitHub successfully delivered webhook and your service accepted it!

---

### Test 3D: Check Webhook Logs
**Command:**
```powershell
kubectl logs -f -l app=webhook-service --all-containers=true
```

**✅ What to Look For (when GitHub webhook arrives):**
```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Processing webhook payload (attempt 1/4)
INFO:httpx:HTTP Request: POST http://ai-service:8000 "HTTP/1.1 200 OK"
INFO:main:Successfully sent payload to AI service: 200
```

**SUCCESS CRITERIA:**
- [ ] Log shows your repo name
- [ ] Shows "Processing webhook payload"
- [ ] Shows HTTP request to AI service
- [ ] Shows successful response (200) or retry attempt

---

---

## 📊 STAGE 4: Production Monitoring

### Test 4A: Monitor Real-Time Logs
**Command:**
```bash
kubectl logs -f -l app=webhook-service --all-containers=true
```

**✅ What to Look For (continuous):**

Every time GitHub sends webhook:
```
INFO:     10.244.0.35:54321 - "POST /webhook/github HTTP/1.1" 200 OK
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Processing webhook payload (attempt 1/4)
```

**Success Pattern:**
```
[Fast responses]   < 100ms for each "200 OK"
[Async processing] Background task continues separately
[Proper logging]   Each step is logged
[No errors]        No 500, 404, or exception traces
```

**Failure Pattern:**
```
❌ "Connection refused"
❌ "500 Internal Server Error"
❌ "CrashLoopBackOff"
❌ No response (times out > 30s)
```

---

### Test 4B: Pod Health Status
**Command:**
```powershell
kubectl get pods -l app=webhook-service
```

**✅ What to Look For:**
```
NAME                                   READY   STATUS    RESTARTS   AGE
webhook-service-598877ff44-sqqhh       1/1     Running   0          26m
webhook-service-598877ff44-wjztq       1/1     Running   0          26m
```

**SUCCESS CRITERIA (continuous monitoring):**
- [ ] All pods stay in `Running` status
- [ ] No pods in `CrashLoopBackOff`
- [ ] RESTARTS count doesn't increase frequently
- [ ] AGE keeps increasing (pods live long)

**Where to Watch for Issues:**
```alert
🔴 RESTARTS increasing → Pod is crashing, check logs
🔴 STATUS changes → Something is wrong, investigate
🔴 READY = 0/1 → Pod not healthy
```

---

### Test 4C: Resource Usage
**Command:**
```bash
kubectl top pods -l app=webhook-service
```

**✅ What to Look For:**
```
NAME                                   CPU(m)   MEMORY(Mi)
webhook-service-598877ff44-sqqhh       50m      45Mi
webhook-service-598877ff44-wjztq       40m      42Mi
```

**SUCCESS CRITERIA:**
- [ ] CPU < 500m (our limit)
- [ ] Memory < 256Mi (our limit)
- [ ] Both metrics stay relatively stable
- [ ] No sudden spikes

**Watch for:**
```alert
🔴 CPU > 500m → Throttled, may drop requests
🔴 Memory > 256Mi → May get OOMKilled
🟡 CPU/Memory constantly increasing → Possible memory leak
```

---

---

## 📈 Complete Workflow Success Checklist

### Before Going Live
- [ ] Local health endpoint returns 200
- [ ] Local webhook endpoint returns 200 in < 100ms
- [ ] Logs show "Webhook received and queued"
- [ ] Background processing is working (logs in background)
- [ ] Both webhook pods are Running

### With ngrok
- [ ] ngrok shows "online" status
- [ ] ngrok forwards to localhost:8001
- [ ] ngrok dashboard shows POST requests
- [ ] Responses from ngrok URL are 200

### GitHub Integration
- [ ] GitHub webhook is added and Active
- [ ] GitHub shows "Successful Delivery" (green checkmark)
- [ ] Status Code in GitHub = 200
- [ ] Recent Deliveries show your requests
- [ ] Logs show requests received from GitHub

### Production Ready
- [ ] All pods Running
- [ ] No CrashLoopBackOff
- [ ] Logs show continuous activity
- [ ] Resource usage is normal
- [ ] Multiple deliveries all succeed

---

## 🔍 Troubleshooting Quick Reference

| Issue | Check For | Solution |
|-------|-----------|----------|
| Connection refused | Port-forward status | `kubectl port-forward service/webhook-service 8001:8001` |
| 404 errors | Health endpoint | Check pod logs: `kubectl logs <POD>` |
| 500 errors | Recent restart | Check RESTARTS column in `kubectl get pods` |
| Slow response (> 1s) | CPU/Memory | `kubectl top pods` |
| ngrok not forwarding | ngrok status | Restart ngrok: `ngrok http 8001` |
| GitHub shows timeout | Response time | Response must be < 30s (should be < 100ms) |
| No webhook delivery | GitHub settings | Check URL and Active status |

---

## ✅ Summary

**Your workflow is working correctly when:**

1. ✅ **Local Tests Pass**
   - Health endpoint: 200 OK
   - Webhook endpoint: 200 OK in < 100ms
   - Logs show processing

2. ✅ **ngrok Tests Pass**
   - ngrok status: online
   - Webhook responds: 200 OK
   - Dashboard shows requests

3. ✅ **GitHub Tests Pass**
   - Webhook shows green checkmark
   - Status code: 200
   - Logs show requests received

4. ✅ **Production Healthy**
   - All pods Running
   - No CrashLoopBackOff
   - Normal resource usage
   - Continuous successful deliveries

---

**When all of these are true, your webhook is working perfectly!** 🚀
