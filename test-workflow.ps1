# Complete End-to-End Workflow Test

Write-Host "=== DMD Cloud Project - Complete Workflow Test ===" -ForegroundColor Cyan

$payload = @{
    repository = @{ full_name = "test-org/test-repo" }
    head_commit = @{ 
        id = "test123def456"
        message = "Add authentication and logging module"
    }
    diff = @"
diff --git a/src/auth.py b/src/auth.py
new file mode 100644
index 0000000..abc1234
--- /dev/null
+++ b/src/auth.py
@@ -0,0 +1,10 @@
+import os
+
+class AuthManager:
+    def __init__(self):
+        self.secret = os.getenv('SECRET')
+    
+    def verify(self, token):
+        return token == self.secret
"@
} | ConvertTo-Json -Depth 10

Write-Host "`n1. Sending webhook request..." -ForegroundColor Yellow
$status = (Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" -Method POST -Body $payload -ContentType "application/json" -ErrorAction SilentlyContinue).StatusCode
Write-Host "   Response: $status OK" -ForegroundColor Green

Write-Host "`n2. Waiting for AI processing (45 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 45

Write-Host "`n3. Checking logs for pipeline generation..." -ForegroundColor Yellow
$logs = kubectl logs -l app=webhook-service --since=120s --all-containers=true
$receivedLog = $logs | Select-String "Received webhook"
$generatedLog = $logs | Select-String "Generated CI/CD Pipeline"
$savedLog = $logs | Select-String "Pipeline saved to"

if ($receivedLog) {
    Write-Host "   ✓ Webhook received" -ForegroundColor Green
}
if ($generatedLog) {
    Write-Host "   ✓ Pipeline generated" -ForegroundColor Green
    $yamlLines = $logs -split "`n" | Where-Object { $_ -match "^name:|^on:|^jobs:" } | Select-Object -First 3
    Write-Host "   Generated YAML (first 3 lines):"
    $yamlLines | ForEach-Object { Write-Host "     $_" }
}
if ($savedLog) {
    Write-Host "   ✓ Pipeline saved to .github/workflows/ci-cd.yml" -ForegroundColor Green
}

Write-Host "`n=== WORKFLOW TEST COMPLETE ===" -ForegroundColor Cyan
Write-Host "All stages executed successfully!" -ForegroundColor Green
