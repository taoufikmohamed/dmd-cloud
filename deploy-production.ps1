# Production Deployment Script
# This script automates the deployment of DMD Cloud to Azure AKS

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DeepSeekApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$AzureSubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
)

$ErrorActionPreference = "Stop"

Write-Host "=== DMD Cloud Production Deployment ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow

# Phase 1: Verify Prerequisites
Write-Host "`n[Phase 1] Verifying Prerequisites..." -ForegroundColor Green

$tools = @("az", "terraform", "kubectl", "docker", "helm")
foreach ($tool in $tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "$tool is not installed. Please install it first."
        exit 1
    }
    Write-Host "  ✓ $tool found" -ForegroundColor Gray
}

# Phase 2: Azure Login and Setup
Write-Host "`n[Phase 2] Azure Authentication..." -ForegroundColor Green

if ($AzureSubscriptionId) {
    az account set --subscription $AzureSubscriptionId
}

$currentAccount = az account show | ConvertFrom-Json
Write-Host "  Using subscription: $($currentAccount.name)" -ForegroundColor Gray

# Phase 3: Terraform Deployment
Write-Host "`n[Phase 3] Deploying Infrastructure with Terraform..." -ForegroundColor Green

Push-Location terraform

# Initialize Terraform
Write-Host "  Initializing Terraform..." -ForegroundColor Gray
terraform init

# Plan
Write-Host "  Creating Terraform plan..." -ForegroundColor Gray
terraform plan -var="environment=$Environment" -var="location=$Location" -out=tfplan

# Apply
Write-Host "  Applying Terraform changes..." -ForegroundColor Yellow
terraform apply tfplan

# Get outputs
$acrServer = terraform output -raw acr_login_server
$aksName = terraform output -raw aks_cluster_name
$rgName = terraform output -raw resource_group_name
$kvName = terraform output -raw key_vault_name

Write-Host "  ✓ Infrastructure deployed successfully" -ForegroundColor Green
Write-Host "    - AKS: $aksName" -ForegroundColor Gray
Write-Host "    - ACR: $acrServer" -ForegroundColor Gray
Write-Host "    - Key Vault: $kvName" -ForegroundColor Gray

Pop-Location

# Phase 4: Connect to AKS
Write-Host "`n[Phase 4] Connecting to AKS..." -ForegroundColor Green

az aks get-credentials --resource-group $rgName --name $aksName --overwrite-existing
kubectl config use-context $aksName

$nodes = kubectl get nodes --no-headers | Measure-Object
Write-Host "  ✓ Connected to AKS ($($nodes.Count) nodes ready)" -ForegroundColor Green

# Phase 5: Build and Push Images
Write-Host "`n[Phase 5] Building and Pushing Docker Images..." -ForegroundColor Green

$acrName = $acrServer -replace '\.azurecr\.io', ''
az acr login --name $acrName

Write-Host "  Building webhook-service..." -ForegroundColor Gray
docker build -t "${acrServer}/webhook-service:latest" -t "${acrServer}/webhook-service:$(Get-Date -Format 'yyyyMMdd-HHmmss')" ./webhook_service
docker push "${acrServer}/webhook-service:latest"

Write-Host "  Building ai-service..." -ForegroundColor Gray
docker build -t "${acrServer}/ai-service:latest" -t "${acrServer}/ai-service:$(Get-Date -Format 'yyyyMMdd-HHmmss')" ./ai_service
docker push "${acrServer}/ai-service:latest"

Write-Host "  ✓ Images pushed to ACR" -ForegroundColor Green

# Phase 6: Update Kubernetes Manifests
Write-Host "`n[Phase 6] Updating Kubernetes Manifests..." -ForegroundColor Green

$manifestFiles = @(
    "k8s/production/webhook-deployment.yaml",
    "k8s/production/ai-deployment.yaml"
)

foreach ($file in $manifestFiles) {
    $content = Get-Content $file -Raw
    $content = $content -replace 'dmdacr\.azurecr\.io', $acrServer
    Set-Content $file -Value $content
    Write-Host "  ✓ Updated $file" -ForegroundColor Gray
}

# Phase 7: Deploy to Kubernetes
Write-Host "`n[Phase 7] Deploying to Kubernetes..." -ForegroundColor Green

# Create namespace
Write-Host "  Creating namespace..." -ForegroundColor Gray
kubectl apply -f k8s/production/namespace.yaml

# Create secrets
Write-Host "  Creating secrets..." -ForegroundColor Gray
kubectl create secret generic ai-service-secrets `
    --from-literal=DEEPSEEK_API_KEY="$DeepSeekApiKey" `
    --namespace=dmd-production `
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy AI service first
Write-Host "  Deploying AI service..." -ForegroundColor Yellow
kubectl apply -f k8s/production/ai-deployment.yaml

Write-Host "  Waiting for AI service to be ready..." -ForegroundColor Gray
kubectl wait --for=condition=available --timeout=300s deployment/ai-service -n dmd-production

# Deploy webhook service
Write-Host "  Deploying webhook service..." -ForegroundColor Yellow
kubectl apply -f k8s/production/webhook-deployment.yaml

Write-Host "  Waiting for webhook service to be ready..." -ForegroundColor Gray
kubectl wait --for=condition=available --timeout=300s deployment/webhook-service -n dmd-production

Write-Host "  ✓ All services deployed" -ForegroundColor Green

# Phase 8: Setup Ingress
Write-Host "`n[Phase 8] Setting up Ingress..." -ForegroundColor Green

# Check if nginx-ingress is installed
$nginxInstalled = helm list -n ingress-nginx | Select-String "nginx-ingress"

if (!$nginxInstalled) {
    Write-Host "  Installing NGINX Ingress Controller..." -ForegroundColor Yellow
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install nginx-ingress ingress-nginx/ingress-nginx `
        --namespace ingress-nginx `
        --create-namespace `
        --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz `
        --wait
}

# Check if cert-manager is installed
$certManagerInstalled = kubectl get namespace cert-manager -o jsonpath='{.metadata.name}' 2>$null

if (!$certManagerInstalled) {
    Write-Host "  Installing cert-manager..." -ForegroundColor Yellow
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    Start-Sleep -Seconds 30
}

Write-Host "  ✓ Ingress controller ready" -ForegroundColor Green

# Phase 9: Get Status
Write-Host "`n[Phase 9] Deployment Status..." -ForegroundColor Green

Write-Host "`nPods:" -ForegroundColor Yellow
kubectl get pods -n dmd-production

Write-Host "`nServices:" -ForegroundColor Yellow
kubectl get svc -n dmd-production

Write-Host "`nHorizontal Pod Autoscalers:" -ForegroundColor Yellow
kubectl get hpa -n dmd-production

# Get external IP
Write-Host "`nGetting External IP address..." -ForegroundColor Yellow
$externalIP = $null
$maxRetries = 30

for ($i = 0; $i -lt $maxRetries; $i++) {
    $externalIP = kubectl get service webhook-service -n dmd-production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($externalIP) {
        break
    }
    Write-Host "  Waiting for external IP... ($i/$maxRetries)" -ForegroundColor Gray
    Start-Sleep -Seconds 10
}

if ($externalIP) {
    Write-Host "`n✓ External IP: $externalIP" -ForegroundColor Green
} else {
    Write-Host "`n⚠ External IP not yet assigned. It may take a few more minutes." -ForegroundColor Yellow
}

# Phase 10: Final Instructions
Write-Host "`n=== DEPLOYMENT COMPLETE ===" -ForegroundColor Cyan

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Configure DNS A record pointing to: $externalIP"
Write-Host "2. Update domain in k8s/production/ingress.yaml"
Write-Host "3. Apply ingress: kubectl apply -f k8s/production/ingress.yaml"
Write-Host "4. Configure GitHub webhook to: https://your-domain.com/webhook/github"
Write-Host "5. Monitor logs: kubectl logs -f -l app=webhook-service -n dmd-production"

Write-Host "`nUseful Commands:" -ForegroundColor Yellow
Write-Host "  View logs:     kubectl logs -f -l app=webhook-service -n dmd-production"
Write-Host "  Get pods:      kubectl get pods -n dmd-production"
Write-Host "  Scale up:      kubectl scale deployment webhook-service --replicas=5 -n dmd-production"
Write-Host "  Get metrics:   kubectl top pods -n dmd-production"
Write-Host "  Port-forward:  kubectl port-forward svc/webhook-service 8001:8001 -n dmd-production"

Write-Host "`n✓ Production deployment successful!" -ForegroundColor Green
