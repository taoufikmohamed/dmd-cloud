# Testing Webhook with ngrok 🌐

Follow these steps to test your webhook through ngrok and integrate with GitHub.

---

## Step 1: Start ngrok Tunnel

Open a **new PowerShell terminal** and run:

```powershell
ngrok http 8001
```

You'll see output like:
```
ngrok                                                                            (Go to http://localhost:4040 to see request/response details)

URL: https://abc123defg45-xyz.ngrok-free.dev
```

**Copy the HTTPS URL** - you'll need it for testing and GitHub configuration.

---

## Step 2: Test Webhook via ngrok (Local Test)

In another terminal, replace `YOUR_NGROK_URL` with the URL from step 1:

```powershell
$NgrokUrl = "https://abc123defg45-xyz.ngrok-free.dev"

Invoke-WebRequest -Uri "$NgrokUrl/webhook/github" `
  -Method POST `
  -ContentType "application/json" `
  -Body (Get-Content test-webhook.json -Raw) `
  -UseBasicParsing
```

**Expected Response:**
```
Status Code: 200
Message: "Webhook received and queued for processing"
```

---

## Step 3: Monitor ngrok Dashboard

Open http://localhost:4040 to see:
- All requests hitting your webhook
- Request headers and body
- Response status codes
- Real-time logs

---

## Step 4: Configure GitHub Webhook

1. Go to **Settings → Webhooks** in your repo:
   https://github.com/taoufikmohamed/dmd-cloud/settings/hooks

2. Click **"Add webhook"** (or edit existing)

3. Fill in the form:
   
   | Field | Value |
   |-------|-------|
   | **Payload URL** | `https://YOUR_NGROK_URL/webhook/github` |
   | **Content type** | `application/json` |
   | **Secret** | (Leave empty for now) |
   | **Events** | ✅ Send me only push events |
   | **Active** | ✅ Checked |

4. Click **"Add webhook"**

---

## Step 5: Test GitHub Integration

### Option A: Use GitHub UI
1. Go to **Webhooks** settings
2. Click the webhook you just created
3. Scroll to **"Recent Deliveries"**
4. Click the 🔄 icon next to any delivery to redeliver
5. Watch for ✅ green checkmark (success) or ❌ red X (failure)

### Option B: Manual Test
Push a commit to master:
```bash
git add .
git commit -m "Testing webhook"
git push origin master
```

GitHub will automatically send a webhook event to your ngrok URL.

---

## Step 6: Monitor Webhook Processing

Watch the webhook logs in real-time:

```powershell
kubectl logs -f -l app=webhook-service --all-containers=true
```

You should see:
```
INFO:main:Received webhook for repository: taoufikmohamed/dmd-cloud
INFO:main:Processing webhook payload (attempt 1/4)
INFO:httpx:HTTP Request: POST http://ai-service:8000 "HTTP/1.1 ..."
```

---

## Troubleshooting

### GitHub shows "Couldn't deliver this payload"

**Check ngrok status:**
- ✅ Is ngrok still running? (Look for "tunneling" in output)
- ✅ Is the URL still valid? (ngrok URLs expire every ~8 hours)

**Check pod logs:**
```powershell
kubectl logs -l app=webhook-service --tail=50 | Select-String "error|failed" -Context 2
```

**Restart everything:**
```powershell
# Restart port-forward
kubectl port-forward service/webhook-service 8001:8001

# Restart webhook service
kubectl rollout restart deployment/webhook-service
```

### Response shows 404 or Connection Refused

Make sure:
```powershell
# 1. Check pods are running
kubectl get pods -l app=webhook-service

# 2. Check port-forward is active
kubectl port-forward service/webhook-service 8001:8001

# 3. Test locally first
Invoke-WebRequest http://localhost:8001/health
```

### GitHub webhook test fails but local test works

1. Check ngrok is still running
2. Verify ngrok URL hasn't expired (restart if needed)
3. Check GitHub webhook URL matches ngrok URL exactly
4. Look at ngrok dashboard (http://localhost:4040) for headers/response details

---

## Expected Behavior ✅

When everything is working:

1. **GitHub sends webhook** → ngrok receives it
2. **ngrok forwards** → http://localhost:8001/webhook/github
3. **Webhook service responds** → 200 OK (in < 1 second)
4. **Processing happens** → asynchronously in background
5. **GitHub shows** → ✅ Success (green checkmark)
6. **Logs show** → "Webhook received and queued for processing"

---

## Keep ngrok Running

To keep ngrok running during development:

```powershell
# Use ngrok with custom domain (if you have Pro)
ngrok http --domain=your-domain.ngrok.app 8001

# Or test with the free dynamic URL
ngrok http 8001
```

Each time you restart ngrok, you'll get a new URL. Update GitHub webhook settings accordingly.

---

## Long-term Deployment (Replace ngrok)

For production:
- Use actual domain with HTTPS certificate
- Update GitHub webhook with permanent domain
- Replace `https://xyz.ngrok-free.dev` with `https://yourdomain.com`

---

## Test with Real Events 🎯

Once GitHub is configured, real webhook events will trigger automatically:
- Push to a branch
- Create a pull request
- Merge code
- Tag a release
- etc.

All will be captured and logged!

---

**You're all set!** Your webhook is ready for GitHub integration. 🚀
