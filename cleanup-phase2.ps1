# DMD Cloud Project - Phase 2 Cleanup Script
# This script removes redundant files identified after the first cleanup

$ErrorActionPreference = "Stop"

Write-Host "=== DMD Cloud Project - Phase 2 Cleanup ===" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd')" -ForegroundColor Yellow
Write-Host ""

$filesToDelete = @(
    # Unused PNG images (not referenced in any documentation)
    #"Automating-DevOps-with-AI.png",
    #"DMD-Cloud-Architecture.png",
    
    # Redundant deployment documentation (covered in README.md)
    "DEPLOYMENT_CHECKLIST.md",
    "DEPLOYMENT_SUMMARY.md",
    "PRODUCTION_DEPLOYMENT.md",
    "QUICK_REFERENCE.md",
    "FILE_STRUCTURE.md",
    
    # Incomplete/unused GitHub workflow
    ".github\workflows\cd.yml",
    
    # Template file (production uses actual secrets)
    "k8s\ai-service-secret.template.yaml"
)

Write-Host "Files to be deleted:" -ForegroundColor Yellow
$filesToDelete | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
Write-Host ""

# Ask for confirmation
$confirmation = Read-Host "Do you want to proceed with deletion? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Cleanup cancelled." -ForegroundColor Red
    exit 0
}

Write-Host ""
Write-Host "Starting cleanup..." -ForegroundColor Green

$deletedCount = 0
$notFoundCount = 0

foreach ($file in $filesToDelete) {
    $fullPath = Join-Path $PSScriptRoot $file
    
    if (Test-Path $fullPath) {
        try {
            Remove-Item $fullPath -Force
            Write-Host "  ✓ Deleted: $file" -ForegroundColor Green
            $deletedCount++
        }
        catch {
            Write-Host "  ✗ Failed to delete: $file - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  ⊘ Not found: $file" -ForegroundColor DarkGray
        $notFoundCount++
    }
}

Write-Host ""
Write-Host "=== Cleanup Summary ===" -ForegroundColor Cyan
Write-Host "Files deleted: $deletedCount" -ForegroundColor Green
Write-Host "Files not found: $notFoundCount" -ForegroundColor Yellow
Write-Host ""
Write-Host "✅ Cleanup completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Remaining essential files:" -ForegroundColor Yellow
Write-Host "  Documentation:" -ForegroundColor White
Write-Host "    - README.md (comprehensive guide)" -ForegroundColor Gray
Write-Host "    - ARCHITECTURE.md (technical details)" -ForegroundColor Gray
Write-Host "    - CLEANUP_SUMMARY.md (history)" -ForegroundColor Gray
Write-Host "  Testing:" -ForegroundColor White
Write-Host "    - test-workflow.ps1" -ForegroundColor Gray
Write-Host "    - test-webhook.json" -ForegroundColor Gray
Write-Host "  Deployment:" -ForegroundColor White
Write-Host "    - deploy-production.ps1" -ForegroundColor Gray
Write-Host "  CI/CD:" -ForegroundColor White
Write-Host "    - .github/workflows/ci.yml" -ForegroundColor Gray
Write-Host "    - .github/workflows/deploy-production.yml" -ForegroundColor Gray
Write-Host ""
