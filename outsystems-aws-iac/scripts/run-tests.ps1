<#
.SYNOPSIS
  Runs the full offline test pipeline locally (same stages as CI, minus real AWS).

.EXAMPLE
  ./scripts/run-tests.ps1
#>
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

function Invoke-Stage([string] $Name, [scriptblock] $Body) {
  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  & $Body
  if ($LASTEXITCODE -ne 0) { throw "Stage '$Name' failed (exit $LASTEXITCODE)" }
}

Invoke-Stage 'terraform fmt'      { terraform fmt -check -recursive }
Invoke-Stage 'terraform init'     { terraform init -backend=false -input=false }
Invoke-Stage 'terraform validate' { terraform validate }

if (Get-Command tflint -ErrorAction SilentlyContinue) {
  Invoke-Stage 'tflint' { tflint --init; tflint --recursive }
} else { Write-Host 'tflint not installed - skipped' -ForegroundColor Yellow }

if (Get-Command checkov -ErrorAction SilentlyContinue) {
  Invoke-Stage 'checkov' { checkov -d . --config-file .checkov.yaml }
} else { Write-Host 'checkov not installed - skipped' -ForegroundColor Yellow }

Invoke-Stage 'unit tests (mocked AWS)' { terraform test }

foreach ($env in 'dev', 'test', 'prod', 'lifetime') {
  Invoke-Stage "policy tests: $env" { terraform test -test-directory=tests/policy "-var-file=environments/$env.tfvars" }
}

Write-Host "`nAll offline tests passed." -ForegroundColor Green
