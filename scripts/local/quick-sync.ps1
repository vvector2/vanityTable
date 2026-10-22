<#
.SYNOPSIS
  Runs the sync job once locally: fetches the first OLX results page and uploads it to the local API.

.DESCRIPTION
  Usage: quickSync [-Pages 1] [-Query toaletki] [-ApiUrl http://localhost:8000]
  (quickSync.cmd in the repo root calls this script)
  - Needs the app running (launch.cmd in another window): it uploads to the local Listings API.
  - Installs Python dependencies and Playwright Chromium when they are missing.
  - Runs the Lambda handler through syncJob\src\run_local.py.
#>
param(
    # How many OLX results pages to fetch.
    [int]$Pages = 1,
    [string]$Query = "toaletki",
    [string]$ApiUrl = "http://localhost:8000"
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Write-Host "==> Checking the Listings API at $ApiUrl" -ForegroundColor Cyan
try {
    Invoke-RestMethod "$ApiUrl/health" -TimeoutSec 5 | Out-Null
} catch {
    throw "Listings API is not reachable at $ApiUrl. Start the app with launch.cmd first."
}

Write-Host "==> Checking sync job dependencies" -ForegroundColor Cyan
$env:PIPENV_VENV_IN_PROJECT = "1"
Push-Location "$root\syncJob"
try {
    if (-not (Test-Path ".venv")) {
        python -m pipenv install --dev
        if ($LASTEXITCODE -ne 0) { throw "pipenv install failed" }
        python -m pipenv run playwright install chromium
        if ($LASTEXITCODE -ne 0) { throw "playwright install failed" }
    }

    # The local API checks tokens from the dev pool (launch.ps1), so use the dev sync client.
    # Its secret is read from SSM, which needs AWS credentials for the dev account.
    . "$PSScriptRoot\cognito-settings.ps1"
    $cognito = Get-CognitoSettings -Env dev
    $env:LISTING_API_URL = $ApiUrl
    $env:COGNITO_TOKEN_URL = $cognito.TokenUrl
    $env:COGNITO_CLIENT_ID = $cognito.SyncClientId
    $env:COGNITO_CLIENT_SECRET_PARAMETER = $cognito.SyncClientSecretParameter
    $env:COGNITO_SCOPE = "$($cognito.ScopePrefix)/create"
    $env:AWS_DEFAULT_REGION = "eu-central-1"

    Write-Host "==> Syncing $Pages page(s) of '$Query' from OLX" -ForegroundColor Cyan
    python -m pipenv run python src/run_local.py --query $Query --max-pages $Pages
    if ($LASTEXITCODE -ne 0) { throw "Sync failed" }
} finally { Pop-Location }
