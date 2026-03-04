[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DockerUsername,

    [Parameter(Mandatory=$false)]
    [switch]$PushImages,

    [Parameter(Mandatory=$false)]
    [switch]$CommitAndPush,

    [Parameter(Mandatory=$false)]
    [string]$CommitMessage = "chore: update non-deploy CI workflow",

    [Parameter(Mandatory=$false)]
    [string]$Branch = "master",

    [Parameter(Mandatory=$false)]
    [switch]$UseRunTag,

    [Parameter(Mandatory=$false)]
    [switch]$SkipWorkflowUpdate
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Require-Tool {
    param([string]$Tool)
    if (!(Get-Command $Tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found: $Tool"
    }
}

function Build-Image {
    param(
        [string]$Name,
        [string]$Context,
        [string]$Tag,
        [string]$ExtraTag
    )

    Write-Host "Building $Name from $Context" -ForegroundColor Yellow
    docker build -t $Tag -t $ExtraTag $Context
}

$services = @(
    @{ Name = "ai-service"; Context = "./ai_service" },
    @{ Name = "webhook-service"; Context = "./webhook_service" },
    @{ Name = "orchestrator"; Context = "./orchestrator" }
)

$sha = (git rev-parse --short HEAD).Trim()
if ($UseRunTag) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $versionTag = "run-$stamp"
} else {
    $versionTag = $sha
}

Write-Step "Checking prerequisites"
Require-Tool git
Require-Tool docker

Write-Step "Validating repository"
if (!(Test-Path ".github/workflows")) {
    New-Item -ItemType Directory -Path ".github/workflows" -Force | Out-Null
}

if ($PushImages -and [string]::IsNullOrWhiteSpace($DockerUsername)) {
    throw "-DockerUsername is required when using -PushImages"
}

if ($PushImages) {
    Write-Step "Docker login check"
    $configPath = "$env:USERPROFILE\.docker\config.json"
    if (!(Test-Path $configPath)) {
        throw "Docker config not found. Run: docker login"
    }
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    if (!$config.auths -or $config.auths.PSObject.Properties.Count -eq 0) {
        throw "Docker is not logged in. Run: docker login"
    }
    Write-Host "Docker authenticated" -ForegroundColor Gray
}

Write-Step "Building all service images"
foreach ($service in $services) {
    if ($PushImages) {
        $latest = "$DockerUsername/$($service.Name):latest"
        $version = "$DockerUsername/$($service.Name):$versionTag"
    } else {
        $latest = "local/$($service.Name):latest"
        $version = "local/$($service.Name):$versionTag"
    }

    Build-Image -Name $service.Name -Context $service.Context -Tag $latest -ExtraTag $version
}

if ($PushImages) {
    Write-Step "Pushing images"
    foreach ($service in $services) {
        docker push "$DockerUsername/$($service.Name):latest"
        docker push "$DockerUsername/$($service.Name):$versionTag"
    }
}

if (-not $SkipWorkflowUpdate) {
    Write-Step "Creating/updating CI-only workflow"

    $ciWorkflow = @'
name: CI

on:
  push:
    branches: [ master ]
  pull_request:
    branches: [ master ]
  workflow_dispatch:

jobs:
  docker-build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and Push AI Service
        uses: docker/build-push-action@v5
        with:
          context: ./ai_service
          push: true
          provenance: false
          sbom: false
          cache-from: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/ai-service:buildcache
          cache-to: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/ai-service:buildcache,mode=max
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/ai-service:latest
            ${{ secrets.DOCKERHUB_USERNAME }}/ai-service:${{ github.sha }}
            ${{ secrets.DOCKERHUB_USERNAME }}/ai-service:run-${{ github.run_number }}

      - name: Build and Push Webhook Service
        uses: docker/build-push-action@v5
        with:
          context: ./webhook_service
          push: true
          provenance: false
          sbom: false
          cache-from: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/webhook-service:buildcache
          cache-to: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/webhook-service:buildcache,mode=max
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/webhook-service:latest
            ${{ secrets.DOCKERHUB_USERNAME }}/webhook-service:${{ github.sha }}
            ${{ secrets.DOCKERHUB_USERNAME }}/webhook-service:run-${{ github.run_number }}

      - name: Build and Push Orchestrator
        uses: docker/build-push-action@v5
        with:
          context: ./orchestrator
          file: ./orchestrator/Dockerfile
          push: true
          provenance: false
          sbom: false
          cache-from: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/orchestrator:buildcache
          cache-to: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/orchestrator:buildcache,mode=max
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/orchestrator:latest
            ${{ secrets.DOCKERHUB_USERNAME }}/orchestrator:${{ github.sha }}
            ${{ secrets.DOCKERHUB_USERNAME }}/orchestrator:run-${{ github.run_number }}
'@

    Set-Content -Path ".github/workflows/ci.yml" -Value $ciWorkflow -Encoding UTF8
}

if ($CommitAndPush) {
    Write-Step "Committing and pushing changes"

    git add .github/workflows/ci.yml run-workflow-nondeploy.ps1
    $staged = git diff --cached --name-only

    if ([string]::IsNullOrWhiteSpace(($staged | Out-String))) {
        Write-Host "No changes to commit for workflow/script." -ForegroundColor DarkYellow
    } else {
        git commit -m $CommitMessage
        git push origin $Branch
    }
}

Write-Step "Completed"
Write-Host "Non-deployment workflow finished successfully." -ForegroundColor Green
if (-not $PushImages) {
    Write-Host "Images were built locally only. Use -PushImages -DockerUsername <name> to publish." -ForegroundColor DarkYellow
}
if (-not $CommitAndPush) {
    Write-Host "No git push was done. Use -CommitAndPush to publish script/workflow updates." -ForegroundColor DarkYellow
}
