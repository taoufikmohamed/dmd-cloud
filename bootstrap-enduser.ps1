<#
.SYNOPSIS
    One-time bootstrap for end-user automation of DMD Cloud.
.DESCRIPTION
    Supports two platforms:
    - minikube (default): local cluster bootstrap
    - aks: Azure AKS bootstrap

    Goal: after operator setup, end users only push code.
.PARAMETER DeepSeekApiKey
    DeepSeek API key used by ai-service (stored in Kubernetes secret).
.PARAMETER Platform
    Target platform: minikube (default) or aks.
.PARAMETER Domain
    Domain host used to build webhook URL: https://<Domain>/webhook/github.
.PARAMETER WebhookUrl
    Full webhook URL override. Useful for tunnels in Minikube (for example ngrok).
.PARAMETER GitHubToken
    GitHub token with permission to manage repository webhooks.
.PARAMETER RepoOwner
    GitHub repository owner. If omitted, inferred from git remote origin.
.PARAMETER RepoName
    GitHub repository name. If omitted, inferred from git remote origin.
.PARAMETER WebhookSecret
    Optional GitHub webhook secret.
.PARAMETER AzureSubscriptionId
    Azure subscription ID for AKS mode.
.PARAMETER Environment
    Environment suffix used by Terraform naming convention in AKS mode.
.PARAMETER Namespace
    Kubernetes namespace for AKS mode. Ignored in Minikube mode.
.PARAMETER SkipWebhook
    Skip GitHub webhook registration.
.PARAMETER SkipIngressApply
    AKS mode only: patch ingress file but do not apply it.
.EXAMPLE
    .\bootstrap-enduser.ps1 -DeepSeekApiKey "sk-xxx" -Platform minikube -SkipWebhook
.EXAMPLE
    .\bootstrap-enduser.ps1 -DeepSeekApiKey "sk-xxx" -Platform aks -Domain "webhook.example.com" -GitHubToken "ghp_xxx"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DeepSeekApiKey,

    [Parameter(Mandatory=$false)]
    [ValidateSet("minikube", "aks")]
    [string]$Platform = "minikube",

    [Parameter(Mandatory=$false)]
    [string]$Domain,

    [Parameter(Mandatory=$false)]
    [string]$WebhookUrl,

    [Parameter(Mandatory=$false)]
    [string]$GitHubToken,

    [Parameter(Mandatory=$false)]
    [string]$RepoOwner,

    [Parameter(Mandatory=$false)]
    [string]$RepoName,

    [Parameter(Mandatory=$false)]
    [string]$WebhookSecret,

    [Parameter(Mandatory=$false)]
    [string]$AzureSubscriptionId,

    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod",

    [Parameter(Mandatory=$false)]
    [string]$Namespace = "dmd-production",

    [Parameter(Mandatory=$false)]
    [switch]$SkipWebhook,

    [Parameter(Mandatory=$false)]
    [switch]$SkipIngressApply
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Test-ToolInstalled {
    param([string]$Tool)
    if (!(Get-Command $Tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found: $Tool"
    }
}

function Get-GitHubRepoFromRemote {
    $remote = (git config --get remote.origin.url)
    if ([string]::IsNullOrWhiteSpace($remote)) {
        throw "Could not read git remote origin URL. Pass -RepoOwner and -RepoName explicitly."
    }

    if ($remote -match "github\.com[:/]([^/]+)/([^/]+?)(\.git)?$") {
        return @{
            Owner = $matches[1]
            Name  = $matches[2]
        }
    }

    throw "Could not parse GitHub owner/repo from remote URL: $remote"
}

function Get-TerraformOutputOrDefault {
    param(
        [string]$OutputName,
        [string]$DefaultValue
    )

    try {
        $value = terraform output -raw $OutputName 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }
    catch {
        # Fall through to default
    }

    return $DefaultValue
}

function Initialize-AzureLogin {
    Write-Step "Azure authentication check"

    try {
        $null = az account show | ConvertFrom-Json
        Write-Success "Azure CLI is authenticated"
    }
    catch {
        Write-Info "Not logged in. Opening Azure login..."
        az login | Out-Null
    }

    if ($AzureSubscriptionId) {
        az account set --subscription $AzureSubscriptionId
        Write-Success "Selected subscription: $AzureSubscriptionId"
    }

    $account = az account show | ConvertFrom-Json
    Write-Info "Active subscription: $($account.name) ($($account.id))"
}

function Resolve-InfrastructureValues {
    Write-Step "Resolving infrastructure values"

    Push-Location terraform
    try {
        $script:ResourceGroupName = Get-TerraformOutputOrDefault -OutputName "resource_group_name" -DefaultValue "dmd-$Environment-rg"
        $script:AksClusterName = Get-TerraformOutputOrDefault -OutputName "aks_cluster_name" -DefaultValue "dmd-aks-$Environment"
        $script:AcrLoginServer = Get-TerraformOutputOrDefault -OutputName "acr_login_server" -DefaultValue "dmdacr$Environment.azurecr.io"
    }
    finally {
        Pop-Location
    }

    Write-Info "Resource Group: $ResourceGroupName"
    Write-Info "AKS Cluster: $AksClusterName"
    Write-Info "ACR Login Server: $AcrLoginServer"
}

function Connect-Aks {
    Write-Step "Connecting kubectl to AKS"

    az aks get-credentials --resource-group $ResourceGroupName --name $AksClusterName --overwrite-existing | Out-Null
    $nodes = kubectl get nodes --no-headers
    if ([string]::IsNullOrWhiteSpace(($nodes | Out-String))) {
        throw "No AKS nodes visible. Check cluster health and credentials."
    }

    Write-Success "Connected to AKS cluster"
}

function Set-AksSecrets {
    Write-Step "Configuring AKS namespace and secrets"

    kubectl apply -f "k8s/production/namespace.yaml" | Out-Null

    kubectl create secret generic ai-service-secrets `
        --from-literal=DEEPSEEK_API_KEY="$DeepSeekApiKey" `
        --namespace=$Namespace `
        --dry-run=client -o yaml | kubectl apply -f - | Out-Null

    Write-Success "Secret 'ai-service-secrets' configured in namespace '$Namespace'"
}

function Update-AksProductionManifests {
    Write-Step "Patching AKS production manifests"

    $manifestFiles = @(
        "k8s/production/webhook-deployment.yaml",
        "k8s/production/ai-deployment.yaml"
    )

    foreach ($file in $manifestFiles) {
        $content = Get-Content $file -Raw
        $content = [regex]::Replace($content, "[a-z0-9]+\.azurecr\.io", $AcrLoginServer)
        Set-Content -Path $file -Value $content -Encoding UTF8
        Write-Success "Patched ACR reference in $file"
    }

    if (-not [string]::IsNullOrWhiteSpace($Domain)) {
        $ingressFile = "k8s/production/ingress.yaml"
        $ingressContent = Get-Content $ingressFile -Raw
        $ingressContent = $ingressContent -replace "webhook\.yourdomain\.com", $Domain
        Set-Content -Path $ingressFile -Value $ingressContent -Encoding UTF8
        Write-Success "Patched ingress domain in $ingressFile"
    }
}

function Set-AksIngressResource {
    if ($SkipIngressApply) {
        Write-Info "Skipping ingress apply as requested"
        return
    }

    Write-Step "Applying AKS ingress"
    kubectl apply -f "k8s/production/ingress.yaml" | Out-Null
    Write-Success "Ingress applied"
}

function Get-AksWebhookServicePublicIp {
    Write-Step "Checking AKS webhook public IP"

    $ip = ""
    for ($i = 0; $i -lt 18; $i++) {
        $ip = kubectl get service webhook-service -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        if (-not [string]::IsNullOrWhiteSpace($ip)) {
            break
        }
        Start-Sleep -Seconds 10
    }

    if ([string]::IsNullOrWhiteSpace($ip)) {
        Write-Info "LoadBalancer IP is not yet assigned."
        return $null
    }

    Write-Success "Webhook service external IP: $ip"
    return $ip
}

function Initialize-MinikubeContext {
    Write-Step "Minikube context check"

    $status = minikube status --format="{{.Host}}" 2>$null
    if ($LASTEXITCODE -ne 0 -or $status -ne "Running") {
        throw "Minikube is not running. Start it with: minikube start"
    }

    kubectl config use-context minikube | Out-Null
    Write-Success "Minikube is running and kubectl context is set"
}

function Build-MinikubeImages {
    Write-Step "Building images inside Minikube"

    minikube image build -t webhook-service:latest ./webhook_service | Out-Null
    minikube image build -t ai-service:latest ./ai_service | Out-Null

    Write-Success "Built Minikube images: webhook-service:latest, ai-service:latest"
}

function Set-MinikubeSecrets {
    Write-Step "Configuring Minikube secret"

    kubectl create secret generic ai-service-secrets `
        --from-literal=DEEPSEEK_API_KEY="$DeepSeekApiKey" `
        --dry-run=client -o yaml | kubectl apply -f - | Out-Null

    Write-Success "Secret 'ai-service-secrets' configured in namespace 'default'"
}

function Deploy-MinikubeManifests {
    Write-Step "Deploying Minikube manifests"

    kubectl apply -f "k8s/ai-deployment.yaml" | Out-Null
    kubectl apply -f "k8s/webhook-deployment.yaml" | Out-Null

    kubectl rollout status deployment/ai-service --timeout=120s | Out-Null
    kubectl rollout status deployment/webhook-service --timeout=120s | Out-Null

    Write-Success "Minikube services deployed and ready"
}

function Get-MinikubeWebhookServiceUrl {
    Write-Step "Resolving local Minikube service URL"

    $baseUrl = minikube service webhook-service --url
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        Write-Info "Could not resolve Minikube service URL."
        return $null
    }

    $baseUrl = $baseUrl.Trim().TrimEnd('/')
    $url = "$baseUrl/webhook/github"
    Write-Success "Local webhook URL: $url"
    return $url
}

function Resolve-TargetWebhookUrl {
    if (-not [string]::IsNullOrWhiteSpace($WebhookUrl)) {
        return $WebhookUrl.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($Domain)) {
        return "https://$Domain/webhook/github"
    }

    if ($Platform -eq "minikube") {
        return Get-MinikubeWebhookServiceUrl
    }

    return $null
}

function Set-GitHubWebhook {
    param(
        [string]$TargetWebhookUrl
    )

    if ($SkipWebhook) {
        Write-Info "Skipping GitHub webhook registration as requested"
        return
    }

    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        throw "-GitHubToken is required unless -SkipWebhook is provided"
    }

    if ([string]::IsNullOrWhiteSpace($TargetWebhookUrl)) {
        throw "Could not resolve webhook URL. Pass -WebhookUrl or -Domain."
    }

    Write-Step "Registering GitHub webhook"

    if ([string]::IsNullOrWhiteSpace($RepoOwner) -or [string]::IsNullOrWhiteSpace($RepoName)) {
        $repo = Get-GitHubRepoFromRemote
        if ([string]::IsNullOrWhiteSpace($RepoOwner)) { $RepoOwner = $repo.Owner }
        if ([string]::IsNullOrWhiteSpace($RepoName)) { $RepoName = $repo.Name }
    }

    $headers = @{
        Authorization = "Bearer $GitHubToken"
        Accept        = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    $hooksEndpoint = "https://api.github.com/repos/$RepoOwner/$RepoName/hooks"
    $existingHooks = Invoke-RestMethod -Method GET -Uri $hooksEndpoint -Headers $headers
    $targetHook = $existingHooks | Where-Object { $_.config.url -eq $TargetWebhookUrl } | Select-Object -First 1

    $config = @{
        url          = $TargetWebhookUrl
        content_type = "json"
        insecure_ssl = "0"
    }

    if (-not [string]::IsNullOrWhiteSpace($WebhookSecret)) {
        $config.secret = $WebhookSecret
    }

    if ($targetHook) {
        $updateBody = @{
            active = $true
            events = @("push")
            config = $config
        } | ConvertTo-Json -Depth 8

        Invoke-RestMethod -Method PATCH -Uri "$hooksEndpoint/$($targetHook.id)" -Headers $headers -Body $updateBody -ContentType "application/json" | Out-Null
        Write-Success "Updated existing webhook (id=$($targetHook.id))"
    }
    else {
        $createBody = @{
            name   = "web"
            active = $true
            events = @("push")
            config = $config
        } | ConvertTo-Json -Depth 8

        Invoke-RestMethod -Method POST -Uri $hooksEndpoint -Headers $headers -Body $createBody -ContentType "application/json" | Out-Null
        Write-Success "Created GitHub webhook for $RepoOwner/$RepoName"
    }

    Write-Info "Webhook URL: $TargetWebhookUrl"
}

function Show-NextSteps {
    param(
        [string]$TargetWebhookUrl,
        [string]$ExternalIp
    )

    Write-Step "Bootstrap complete"

    if ($Platform -eq "aks") {
        if (-not [string]::IsNullOrWhiteSpace($ExternalIp) -and -not [string]::IsNullOrWhiteSpace($Domain)) {
            Write-Host "1. Create DNS A record: $Domain -> $ExternalIp" -ForegroundColor Yellow
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Domain)) {
            Write-Host "1. Wait for external IP then point DNS A record for $Domain" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "1. Minikube is local-only. For GitHub webhook delivery, expose it via tunnel and use -WebhookUrl" -ForegroundColor Yellow
    }

    if (-not [string]::IsNullOrWhiteSpace($TargetWebhookUrl)) {
        Write-Host "2. Webhook endpoint: $TargetWebhookUrl" -ForegroundColor Yellow
    }

    Write-Host "3. Push code to trigger end-user automation flow" -ForegroundColor Yellow
    if ($Platform -eq "aks") {
        Write-Host "4. Monitor logs: kubectl logs -f -l app=webhook-service -n $Namespace" -ForegroundColor Yellow
    }
    else {
        Write-Host "4. Monitor logs: kubectl logs -f -l app=webhook-service" -ForegroundColor Yellow
    }
}

function Invoke-AksBootstrap {
    Test-ToolInstalled "az"
    Test-ToolInstalled "kubectl"
    Test-ToolInstalled "terraform"
    Test-ToolInstalled "git"

    Initialize-AzureLogin
    Resolve-InfrastructureValues
    Connect-Aks
    Set-AksSecrets
    Update-AksProductionManifests
    Set-AksIngressResource

    $externalIp = Get-AksWebhookServicePublicIp
    $targetWebhookUrl = Resolve-TargetWebhookUrl
    Set-GitHubWebhook -TargetWebhookUrl $targetWebhookUrl
    Show-NextSteps -TargetWebhookUrl $targetWebhookUrl -ExternalIp $externalIp
}

function Invoke-MinikubeBootstrap {
    Test-ToolInstalled "minikube"
    Test-ToolInstalled "kubectl"
    Test-ToolInstalled "git"

    Initialize-MinikubeContext
    Build-MinikubeImages
    Set-MinikubeSecrets
    Deploy-MinikubeManifests

    $targetWebhookUrl = Resolve-TargetWebhookUrl
    Set-GitHubWebhook -TargetWebhookUrl $targetWebhookUrl
    Show-NextSteps -TargetWebhookUrl $targetWebhookUrl -ExternalIp $null
}

function Main {
    Write-Host "`nDMD Cloud End-User Bootstrap" -ForegroundColor Cyan
    Write-Host "--------------------------------" -ForegroundColor Cyan
    Write-Info "Platform: $Platform"

    if ($Platform -eq "aks") {
        Invoke-AksBootstrap
        return
    }

    Invoke-MinikubeBootstrap
}

Main
