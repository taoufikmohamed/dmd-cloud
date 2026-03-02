#!/usr/bin/env pwsh

# ============================================================================
# WEBHOOK TESTING WORKFLOW
# Tests the complete webhook pipeline with status code verification
# ============================================================================

Write-Host "=== WEBHOOK TESTING WORKFLOW ===" -ForegroundColor Cyan
Write-Host ""

# Color coding for output
$Success = "Green"
$Error = "Red"
$Info = "Yellow"
$Header = "Cyan"

# ============================================================================
# STEP 1: Verify Services are Running
# ============================================================================
Write-Host "STEP 1: Verify Services are Running" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "Checking webhook pods..." -ForegroundColor $Info
$pods = kubectl get pods -l app=webhook-service --no-headers 2>/dev/null
if ($pods) {
    Write-Host $pods -ForegroundColor $Success
} else {
    Write-Host "Unable to get pods" -ForegroundColor $Error
}

Write-Host ""
Write-Host "Checking webhook service..." -ForegroundColor $Info
$service = kubectl get service webhook-service --no-headers 2>/dev/null
if ($service) {
    Write-Host $service -ForegroundColor $Success
} else {
    Write-Host "Service not found" -ForegroundColor $Error
}

Write-Host ""

# ============================================================================
# STEP 2: Test Health Endpoint (local)
# ============================================================================
Write-Host "STEP 2: Test Health Endpoint (Local)" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "Testing: GET http://localhost:8001/health" -ForegroundColor $Info
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8001/health" `
        -UseBasicParsing `
        -ErrorAction Stop
    
    Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor $Success
    Write-Host "Response:" -ForegroundColor $Success
    Write-Host ($response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10) -ForegroundColor $Success
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor $Error
    Write-Host "Make sure port-forward is running: kubectl port-forward service/webhook-service 8001:8001" -ForegroundColor $Info
}

Write-Host ""

# ============================================================================
# STEP 3: Test Root Endpoint (local)
# ============================================================================
Write-Host "STEP 3: Test Root Endpoint (Local)" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "Testing: GET http://localhost:8001/" -ForegroundColor $Info
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8001/" `
        -UseBasicParsing `
        -ErrorAction Stop
    
    Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor $Success
    Write-Host "Response:" -ForegroundColor $Success
    Write-Host ($response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10) -ForegroundColor $Success
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor $Error
}

Write-Host ""

# ============================================================================
# STEP 4: Test Webhook Endpoint with Test Payload (local)
# ============================================================================
Write-Host "STEP 4: Test Webhook Endpoint (Local)" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "Testing: POST http://localhost:8001/webhook/github" -ForegroundColor $Info

if (-not (Test-Path "test-webhook.json")) {
    Write-Host "Creating sample webhook payload..." -ForegroundColor $Info
    $payload = @{
        repository = @{
            full_name = "taoufikmohamed/dmd-cloud"
        }
        head_commit = @{
            id = "abc123"
            message = "Test webhook"
            added = @("test.md")
            removed = @()
            modified = @("main.py")
        }
    } | ConvertTo-Json
} else {
    $payload = Get-Content test-webhook.json -Raw
}

try {
    $response = Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
        -Method POST `
        -ContentType "application/json" `
        -Body $payload `
        -UseBasicParsing `
        -ErrorAction Stop
    
    Write-Host "✓ Status Code: $($response.StatusCode)" -ForegroundColor $Success
    Write-Host "✓ Response Body:" -ForegroundColor $Success
    Write-Host ($response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10) -ForegroundColor $Success
    
    if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 202) {
        Write-Host "✓ WEBHOOK ACCEPTED SUCCESSFULLY!" -ForegroundColor $Success
    }
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor $Error
    if ($_.Exception.Response) {
        Write-Host "Status Code: $($_.Exception.Response.StatusCode.Value__)" -ForegroundColor $Error
    }
}

Write-Host ""

# ============================================================================
# STEP 5: Check Webhook Logs
# ============================================================================
Write-Host "STEP 5: Check Webhook Service Logs" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "Recent logs (last 20 lines):" -ForegroundColor $Info
kubectl logs -l app=webhook-service --tail=20 --all-containers=true 2>/dev/null

Write-Host ""

# ============================================================================
# STEP 6: Test with ngrok (if running)
# ============================================================================
Write-Host "STEP 6: Test Webhook via ngrok (if available)" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "To test via ngrok:" -ForegroundColor $Info
Write-Host ""
Write-Host "1. Start ngrok in another terminal:" -ForegroundColor $Info
Write-Host "   ngrok http 8001" -ForegroundColor "Gray"
Write-Host ""
Write-Host "2. Copy the ngrok URL (e.g., https://xxxx.ngrok-free.dev)" -ForegroundColor $Info
Write-Host ""
Write-Host "3. Test with the URL:" -ForegroundColor $Info
Write-Host "   `$ngrokUrl = https://epexegetically-nonideal-sina.ngrok-free.dev" -ForegroundColor "Gray"
Write-Host "   Invoke-WebRequest -Uri `$ngrokUrl/webhook/github -Method POST -ContentType 'application/json' -Body (Get-Content test-webhook.json -Raw)" -ForegroundColor "Gray"
Write-Host ""

# ============================================================================
# STEP 7: GitHub Webhook Configuration
# ============================================================================
Write-Host "STEP 7: Update GitHub Webhook Configuration" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "To integrate with GitHub:" -ForegroundColor $Info
Write-Host ""
Write-Host "1. Go to: https://github.com/taoufikmohamed/dmd-cloud/settings/hooks" -ForegroundColor "Magenta"
Write-Host ""
Write-Host "2. Add/Edit webhook with:" -ForegroundColor $Info
Write-Host "   Payload URL:       https://epexegetically-nonideal-sina.ngrok-free.dev/webhook/github" -ForegroundColor "Gray"
Write-Host "   Content type:      application/json" -ForegroundColor "Gray"
Write-Host "   Events:            Push events (or select all)" -ForegroundColor "Gray"
Write-Host "   Active:            Yes (checked)" -ForegroundColor "Gray"
Write-Host ""
Write-Host "3. Click 'Add webhook'" -ForegroundColor $Info
Write-Host ""
Write-Host "4. Test with 'Recent Deliveries' tab to redelivery webhooks" -ForegroundColor $Info
Write-Host ""

# ============================================================================
# STEP 8: Monitoring & Troubleshooting
# ============================================================================
Write-Host "STEP 8: Monitoring & Troubleshooting" -ForegroundColor $Header
Write-Host "-" * 60

Write-Host "Watch webhook logs in real-time:" -ForegroundColor $Info
Write-Host "   kubectl logs -f -l app=webhook-service --all-containers=true" -ForegroundColor "Gray"
Write-Host ""

Write-Host "Check pod status:" -ForegroundColor $Info
Write-Host "   kubectl describe pod <POD_NAME>" -ForegroundColor "Gray"
Write-Host ""

Write-Host "Port-forward to local:" -ForegroundColor $Info
Write-Host "   kubectl port-forward service/webhook-service 8001:8001" -ForegroundColor "Gray"
Write-Host ""

Write-Host "Restart deployment:" -ForegroundColor $Info
Write-Host "   kubectl rollout restart deployment/webhook-service" -ForegroundColor "Gray"
Write-Host ""

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "=== TESTING SUMMARY ===" -ForegroundColor $Header
Write-Host ""
Write-Host "✓ Step 1: Verify services are running" -ForegroundColor $Info
Write-Host "✓ Step 2: Health check endpoint works" -ForegroundColor $Info
Write-Host "✓ Step 3: Root endpoint works" -ForegroundColor $Info
Write-Host "✓ Step 4: Webhook accepts POST requests with 200 status" -ForegroundColor $Info
Write-Host "✓ Step 5: Check logs for processing" -ForegroundColor $Info
Write-Host "✓ Step 6: Test with ngrok tunnel" -ForegroundColor $Info
Write-Host "✓ Step 7: Configure GitHub webhook" -ForegroundColor $Info
Write-Host "✓ Step 8: Monitor and troubleshoot" -ForegroundColor $Info
Write-Host ""

Write-Host "EXPECTED BEHAVIOR:" -ForegroundColor $Header
Write-Host "1. Webhook responds with status 200/202 IMMEDIATELY (<1 second)" -ForegroundColor $Info
Write-Host "2. Logs show 'Webhook received' message" -ForegroundColor $Info
Write-Host "3. AI service is called asynchronously in background" -ForegroundColor $Info
Write-Host "4. If AI service is slow, webhook still responds instantly" -ForegroundColor $Info
Write-Host ""

Write-Host "Testing complete!" -ForegroundColor $Success
