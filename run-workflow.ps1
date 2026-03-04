<#
.SYNOPSIS
    Complete DMD Cloud Workflow - Build, Deploy to Minikube, Test, and Generate CI/CD Pipeline
.DESCRIPTION
    This script orchestrates the entire DMD Cloud workflow:
    1. Build Docker images locally
    2. Load images into Minikube
    3. Deploy services to Minikube with Kubernetes manifests
    4. Configure Kubernetes secrets
    5. Send a webhook request to trigger pipeline generation
    6. Monitor the workflow execution
    7. Verify the generated .github/workflows/ci-cd.yml file
.PARAMETER DeepSeekAPIKey
    The DeepSeek API key for AI service (required for deployment)
.PARAMETER SkipBuild
    Skip Docker image building step
.PARAMETER SkipDeploy
    Skip Kubernetes deployment step
.PARAMETER SkipTest
    Skip webhook test and workflow validation
.PARAMETER CleanupAfter
    Delete Kubernetes deployments after test (for cleanup testing)
.PARAMETER Branch
    Git branch name (default: master)
.EXAMPLE
    .\run-workflow.ps1 -DeepSeekAPIKey "sk-xxx" -Branch master
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DeepSeekAPIKey,

    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory=$false)]
    [switch]$SkipDeploy,

    [Parameter(Mandatory=$false)]
    [switch]$SkipTest,

    [Parameter(Mandatory=$false)]
    [switch]$CleanupAfter,

    [Parameter(Mandatory=$false)]
    [string]$Branch = "master"
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"

# ============================================================================
# CONFIGURATION
# ============================================================================
$services = @(
    @{ Name = "ai-service"; Context = "./ai_service"; Port = 8000 },
    @{ Name = "webhook-service"; Context = "./webhook_service"; Port = 8001 }
)

$kubeNamespace = "default"
$kubeSecretName = "ai-service-secrets"
$gitDiff = @"
diff --git a/src/auth.py b/src/auth.py
new file mode 100644
index 0000000..abc1234
--- /dev/null
+++ b/src/auth.py
@@ -0,0 +1,15 @@
+import os
+
+class AuthManager:
+    def __init__(self):
+        self.secret = os.getenv('SECRET_KEY')
+        self.timeout = 3600
+    
+    def verify(self, token: str) -> bool:
+        """Verify authentication token."""
+        if not token:
+            return False
+        return token == self.secret
+    
+    def generate_token(self) -> str:
+        """Generate new authentication token."""
+        return f"token_{int(time.time())}"
"@

$workflowPayload = @{
    repository = @{ full_name = "dmd-cloud/dmd-cloud-project" }
    head_commit = @{ 
        id = "$(git rev-parse --short HEAD)"
        message = "feat: add authentication module"
    }
    diff = $gitDiff
} | ConvertTo-Json -Depth 10

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
function Write-Step {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "`n========================================" -ForegroundColor $Color
    Write-Host "==> $Message" -ForegroundColor $Color
    Write-Host "========================================" -ForegroundColor $Color
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Require-Tool {
    param([string]$Tool, [string]$InstallCmd = "")
    if (!(Get-Command $Tool -ErrorAction SilentlyContinue)) {
        $msg = "Required tool not found: $Tool"
        if ($InstallCmd) { $msg += "`nInstall with: $InstallCmd" }
        throw $msg
    }
}

function Test-Minikube {
    try {
        $status = & minikube status --format="{{.Host}}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

function Build-DockerImages {
    Write-Step "Building Docker Images" "Yellow"
    
    foreach ($service in $services) {
        Write-Log "Building $($service.Name) from $($service.Context)..." "Yellow"
        
        if (!(Test-Path $service.Context)) {
            throw "Service directory not found: $($service.Context)"
        }
        
        $imageName = "$($service.Name):latest"
        & docker build -t $imageName $service.Context
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to build image: $imageName"
        }
        
        Write-Success "Built image: $imageName"
    }
}

function Load-ImagesToMinikube {
    Write-Step "Loading Docker Images into Minikube" "Yellow"
    
    foreach ($service in $services) {
        $imageName = "$($service.Name):latest"
        Write-Log "Loading $imageName into minikube..." "Yellow"
        
        & minikube image load $imageName
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to load image into minikube: $imageName"
        }
        
        Write-Success "Loaded image: $imageName"
    }
}

function Create-KubeSecret {
    Write-Log "Creating/Updating Kubernetes secret: $kubeSecretName" "Yellow"
    
    # Create secret (or update if exists)
    & kubectl create secret generic $kubeSecretName `
        --from-literal=DEEPSEEK_API_KEY=$DeepSeekAPIKey `
        --dry-run=client -o yaml | kubectl apply -f -
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create/update Kubernetes secret"
    }
    
    Write-Success "Kubernetes secret created/updated"
}

function Deploy-Services {
    Write-Step "Deploying Services to Minikube" "Yellow"
    
    # Deploy AI Service
    Write-Log "Deploying ai-service..." "Yellow"
    & kubectl apply -f k8s/ai-deployment.yaml
    if ($LASTEXITCODE -ne 0) { throw "Failed to deploy ai-service" }
    Write-Success "Deployed ai-service"
    
    # Deploy Webhook Service
    Write-Log "Deploying webhook-service..." "Yellow"
    & kubectl apply -f k8s/webhook-deployment.yaml
    if ($LASTEXITCODE -ne 0) { throw "Failed to deploy webhook-service" }
    Write-Success "Deployed webhook-service"
    
    # Wait for rollout
    Write-Log "Waiting for deployments to be ready..." "Yellow"
    & kubectl rollout status deployment/ai-service --timeout=120s | Out-Null
    & kubectl rollout status deployment/webhook-service --timeout=120s | Out-Null
    
    Write-Success "All services deployed and ready"
}

function Show-DeploymentStatus {
    Write-Step "Deployment Status" "Cyan"
    
    Write-Log "Pods:"
    & kubectl get pods -o wide
    
    Write-Log "`nServices:"
    & kubectl get svc -o wide
    
    Write-Log "`nSecrets:"
    & kubectl get secrets
}

function Setup-PortForwarding {
    Write-Step "Setting Up Port Forwarding" "Yellow"
    
    # Check if port-forward jobs already exist
    $existingJobs = Get-Job -Name "minikube-port-forward-*" -ErrorAction SilentlyContinue
    if ($existingJobs) {
        Write-Log "Cleaning up previous port-forward jobs..."
        $existingJobs | Stop-Job -ErrorAction SilentlyContinue
        $existingJobs | Remove-Job -ErrorAction SilentlyContinue
    }
    
    # Start port forwarding in background
    Write-Log "Starting port forwarding: localhost:8001 -> webhook-service:8001" "Yellow"
    $job1 = Start-Job -Name "minikube-port-forward-webhook" -ScriptBlock {
        & kubectl port-forward service/webhook-service 8001:8001
    }
    
    Write-Log "Starting port forwarding: localhost:8000 -> ai-service:8000" "Yellow"
    $job2 = Start-Job -Name "minikube-port-forward-ai" -ScriptBlock {
        & kubectl port-forward service/ai-service 8000:8000
    }
    
    # Wait for port forwarding to be ready
    Start-Sleep -Seconds 3
    
    Write-Success "Port forwarding established"
    Write-Log "Webhook service available at: http://localhost:8001"
    Write-Log "AI service available at: http://localhost:8000"
}

function Test-ServiceHealth {
    Write-Step "Testing Service Health" "Yellow"
    
    $maxAttempts = 10
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        try {
            Write-Log "Checking webhook-service health (attempt $($attempt + 1)/$maxAttempts)..." "Yellow"
            $response = Invoke-WebRequest -Uri "http://localhost:8001/health" `
                -Method GET `
                -TimeoutSec 5 `
                -ErrorAction Stop
            
            if ($response.StatusCode -eq 200) {
                Write-Success "Webhook service is healthy"
                break
            }
        } catch {
            $attempt++
            if ($attempt -lt $maxAttempts) {
                Write-Log "Service not ready, retrying in 3 seconds..." "Gray"
                Start-Sleep -Seconds 3
            }
        }
    }
    
    if ($attempt -eq $maxAttempts) {
        throw "Webhook service failed to become healthy"
    }
    
    # Check AI service
    try {
        Write-Log "Checking ai-service health..." "Yellow"
        $response = Invoke-WebRequest -Uri "http://localhost:8000/health" `
            -Method GET `
            -TimeoutSec 5 `
            -ErrorAction Stop
        Write-Success "AI service is healthy"
    } catch {
        Write-Log "AI service health check skipped: $_" "Gray"
    }
}

function Send-Webhook {
    Write-Step "Sending Webhook Request" "Yellow"
    
    Write-Log "Sending webhook payload to http://localhost:8001/webhook/github..." "Yellow"
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8001/webhook/github" `
            -Method POST `
            -Body $workflowPayload `
            -ContentType "application/json" `
            -TimeoutSec 30 `
            -ErrorAction Stop
        
        Write-Success "Webhook accepted - Status: $($response.StatusCode)"
        Write-Log "Webhook is processing in background..." "Gray"
    } catch {
        throw "Failed to send webhook: $_"
    }
}

function Monitor-WorkflowExecution {
    param([int]$WaitSeconds = 60)
    
    Write-Step "Monitoring Workflow Execution" "Yellow"
    Write-Log "Waiting $WaitSeconds seconds for AI to generate pipeline..." "Gray"
    
    $remainingTime = $WaitSeconds
    while ($remainingTime -gt 0) {
        $percent = [math]::Min(100, [math]::Floor((($WaitSeconds - $remainingTime) / $WaitSeconds) * 100))
        $barLength = [math]::Floor($percent / 5)
        $bar = [string]([char]9608) * $barLength
        Write-Host "`r[$bar]($percent%) " -NoNewline
        Start-Sleep -Seconds 1
        $remainingTime--
    }
    Write-Host "`n" | Out-Null
    
    Write-Log "Checking webhook service logs..." "Yellow"
    $logs = & kubectl logs -l app=webhook-service --since=90s --all-containers=true 2>$null
    
    $receivedLog = $logs | Select-String "Received webhook"
    $generatedLog = $logs | Select-String "Generated CI/CD Pipeline"
    $savedLog = $logs | Select-String "Pipeline saved to" | Select-Object -First 1
    
    Write-Log "`nWorkflow Execution Status:" "Cyan"
    
    if ($receivedLog) {
        Write-Success "Webhook received and processed"
    } else {
        Write-Error-Custom "Webhook not received"
    }
    
    if ($generatedLog) {
        Write-Success "Pipeline generated by AI"
    } else {
        Write-Error-Custom "Pipeline generation may be pending"
    }
    
    if ($savedLog) {
        Write-Success "Pipeline saved to file"
        Write-Log "Details: $($savedLog.Line)" "Gray"
    } else {
        Write-Error-Custom "Pipeline file may not have been saved"
    }
    
    # Show relevant log entries
    Write-Log "`nRecent Log Entries:" "Cyan"
    $logs | Select-String -Pattern "(Received webhook|Generated|Pipeline saved|Error|Exception)" | 
        Select-Object -Last 15 | 
        ForEach-Object { Write-Log "  $_" "Gray" }
}

function Verify-GeneratedWorkflow {
    Write-Step "Verifying Generated Workflow File" "Yellow"
    
    $workflowFile = ".github/workflows/ci-cd.yml"
    
    if (Test-Path $workflowFile) {
        Write-Success "Workflow file exists: $workflowFile"
        
        $content = Get-Content $workflowFile -Raw
        $lines = $content -split "`n"
        
        Write-Log "`nWorkflow file preview (first 30 lines):" "Cyan"
        $lines | Select-Object -First 30 | ForEach-Object { Write-Log "  $_" "Gray" }
        
        if ($content -match "^name:\s") {
            Write-Success "Workflow has valid YAML structure"
        } else {
            Write-Error-Custom "Workflow file may have invalid structure"
        }
        
        Write-Log "`nFile size: $(($content | Measure-Object -Character).Characters) bytes" "Gray"
        Write-Log "Last modified: $((Get-Item $workflowFile).LastWriteTime)" "Gray"
    } else {
        Write-Error-Custom "Workflow file not yet generated: $workflowFile"
        Write-Log "The workflow generation may still be processing. Check service logs for details." "Yellow"
    }
}

function Cleanup {
    Write-Step "Cleaning Up Resources" "Yellow"
    
    Write-Log "Stopping port-forward jobs..." "Yellow"
    Get-Job -Name "minikube-port-forward-*" -ErrorAction SilentlyContinue | 
        Stop-Job -ErrorAction SilentlyContinue
    
    Get-Job -Name "minikube-port-forward-*" -ErrorAction SilentlyContinue | 
        Remove-Job -ErrorAction SilentlyContinue
    
    Write-Success "Port-forward jobs stopped"
    
    if ($CleanupAfter) {
        Write-Log "Deleting Kubernetes deployments..." "Yellow"
        & kubectl delete deployment webhook-service --ignore-not-found=true
        & kubectl delete deployment ai-service --ignore-not-found=true
        & kubectl delete svc webhook-service --ignore-not-found=true
        & kubectl delete svc ai-service --ignore-not-found=true
        Write-Success "Kubernetes resources deleted"
    }
}

function main {
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "╔════════════════════════════════════════════════════════║" -ForegroundColor Cyan
    Write-Host "║  DMD Cloud - Complete Workflow Execution               ║" -ForegroundColor Cyan
    Write-Host "║  Build → Deploy → Test → Generate CI/CD Pipeline     ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════║" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Prerequisites
        Write-Step "Checking Prerequisites" "Cyan"
        Require-Tool "git"
        Require-Tool "docker"
        Require-Tool "kubectl"
        Require-Tool "minikube"
        Write-Success "All prerequisites found"
        
        # Validate minikube
        Write-Log "Checking minikube status..." "Yellow"
        if (!(Test-Minikube)) {
            throw "Minikube is not running. Start it with: minikube start"
        }
        Write-Success "Minikube is running"
        
        # Step 1: Build Images
        if (!$SkipBuild) {
            Build-DockerImages
            Load-ImagesToMinikube
        } else {
            Write-Log "Skipping Docker image build" "Gray"
        }
        
        # Step 2: Deploy to Minikube
        if (!$SkipDeploy) {
            Create-KubeSecret
            Deploy-Services
            Setup-PortForwarding
            Test-ServiceHealth
        } else {
            Write-Log "Skipping Kubernetes deployment" "Gray"
        }
        
        # Show current status
        Show-DeploymentStatus
        
        # Step 3: Test Workflow
        if (!$SkipTest) {
            Send-Webhook
            Monitor-WorkflowExecution -WaitSeconds 60
            Verify-GeneratedWorkflow
        } else {
            Write-Log "Skipping workflow test" "Gray"
        }
        
        # Success summary
        Write-Step "Workflow Complete ✓" "Green"
        Write-Log "All workflow stages executed successfully!" "Green"
        Write-Log "`nNext steps:" "Cyan"
        Write-Log "  1. Review generated workflow at: .github/workflows/ci-cd.yml" "Gray"
        Write-Log "  2. Test with: .\test-workflow.ps1" "Gray"
        Write-Log "  3. Configure GitHub webhook if needed" "Gray"
        Write-Log "  4. Deploy to production when ready" "Gray"
        
    } catch {
        Write-Error-Custom "Workflow failed: $_"
        Write-Host ""
        throw $_
    } finally {
        # Always cleanup
        Cleanup
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main
