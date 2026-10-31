<#
.SYNOPSIS
  Runs the sync job once locally: fetches the first OLX results page and uploads it to the local API.

.DESCRIPTION
  Usage: quickSync [-Pages 1] [-Query toaletki] [-ApiUrl http://127.0.0.1:8000] [-JobId <id>]
  (quickSync.cmd in the repo root calls this script)
  - Needs the app running (launch.cmd in another window): it uploads to the local Listings API.
  - Installs Python dependencies and Playwright Chromium when they are missing.
  - The UI's scan button only creates a scan job locally (no Lambda to invoke); pass the id
    the API logs as -JobId, so this run reports on that job.
  - Runs the Lambda handler through syncJob\src\local\run_local.py.
#>
param(
    # How many OLX results pages to fetch.
    [int]$Pages = 1,
    [string]$Query = "toaletki",
    # 127.0.0.1, not localhost: localhost tries IPv6 first and costs about 2 s per request.
    [string]$ApiUrl = "http://127.0.0.1:8000",
    # Scan job to report on, e.g. one created by the UI's scan button.
    [string]$JobId
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
Push-Location "$root\syncJob\src"
try {
    # pipenv finds syncJob\Pipfile from src; the venv lives next to it.
    if (-not (Test-Path "..\.venv")) {
        python -m pipenv install --dev
        if ($LASTEXITCODE -ne 0) { throw "pipenv install failed" }
        python -m pipenv run playwright install chromium
        if ($LASTEXITCODE -ne 0) { throw "playwright install failed" }
    }

    # The local API checks tokens from the dev pool (launch.ps1), so use the dev sync client.
    # Its secret is read from SSM here, which needs AWS credentials for the dev account.
    . "$PSScriptRoot\cognito-settings.ps1"
    $cognito = Get-CognitoSettings -Env dev
    $env:LISTING_API_URL = $ApiUrl
    $env:COGNITO_TOKEN_URL = $cognito.TokenUrl
    $env:COGNITO_CLIENT_ID = $cognito.SyncClientId
    $env:COGNITO_CLIENT_SECRET = Get-SsmSecret $cognito.SyncClientSecretParameter
    $env:COGNITO_SCOPE = "$($cognito.ScopePrefix)/create"
    $env:AWS_DEFAULT_REGION = "eu-central-1"

    Write-Host "==> Syncing $Pages page(s) of '$Query' from OLX" -ForegroundColor Cyan
    $jobArgs = if ($JobId) { @("--job-id", $JobId) } else { @() }
    python -m pipenv run python -m local.run_local --query $Query --max-pages $Pages @jobArgs
    if ($LASTEXITCODE -ne 0) { throw "Sync failed" }
} finally { Pop-Location }
