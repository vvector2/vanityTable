<#
.SYNOPSIS
  Runs the whole app locally: LocalStack (DynamoDB), the listings API, the sync job and the UI.

.DESCRIPTION
  Usage: launch [-UiPort 5174]   (launch.cmd in the repo root calls this script)
  - Starts docker-compose.local-dependencies.yml through WSL (Docker is not installed on Windows).
  - Installs Python and npm dependencies when they are missing.
  - Runs the API on http://localhost:8000 and the UI on http://localhost:5173 (or -UiPort).
  - Runs the sync job behind a local Lambda Invoke API on http://localhost:9001
    (syncJob\src\local\local_lambda.py), so the UI's scan button starts a real sync into the local API.
  - Sign-in and API tokens use the dev Cognito pool, so it needs AWS credentials for the dev account
    (reads the dev Terraform outputs, see cognito-settings.ps1).
  Ctrl+C stops everything, including LocalStack. The table is recreated empty on every launch; fill it with the
  scan button or quickSync.
#>
param(
    # UI port; change it when 5173 is already taken.
    [int]$UiPort = 5173
)

$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$compose = "docker compose -f docker-compose.local-dependencies.yml"

function Invoke-Wsl([string]$command) {
    # WSL starts in the Windows working directory mapped to /mnt/c/...
    Push-Location $root
    try { wsl -e sh -c $command } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "WSL command failed: $command" }
}

# WSL shuts its VM down (and Docker with it) shortly after the last wsl process exits,
# so keep one running for as long as the app runs.
. "$PSScriptRoot\cognito-settings.ps1"
Write-Host "==> Reading the dev Cognito settings from Terraform" -ForegroundColor Cyan
$cognito = Get-CognitoSettings -Env dev
if ($UiPort -ne 5173) { Write-Warning "Cognito redirects sign-in back to http://localhost:5173/ only (dev_callback_urls)." }

$wslKeepAlive = Start-Process wsl -ArgumentList "-e", "sleep", "infinity" -WindowStyle Hidden -PassThru
$api = $null
$sync = $null

try {
    Write-Host "==> Starting local dependencies (LocalStack) in WSL" -ForegroundColor Cyan
    Invoke-Wsl "$compose up -d --wait"

    Write-Host "==> Checking backend dependencies" -ForegroundColor Cyan
    $env:PIPENV_VENV_IN_PROJECT = "1"
    Push-Location "$root\listingApi"
    try {
        if (-not (Test-Path ".venv")) { python -m pipenv install --dev }
    } finally { Pop-Location }

    Write-Host "==> Checking sync job dependencies" -ForegroundColor Cyan
    Push-Location "$root\syncJob"
    try {
        if (-not (Test-Path ".venv")) {
            python -m pipenv install --dev
            if ($LASTEXITCODE -ne 0) { throw "pipenv install failed" }
            python -m pipenv run playwright install chromium
            if ($LASTEXITCODE -ne 0) { throw "playwright install failed" }
        }
    } finally { Pop-Location }

    Write-Host "==> Checking UI dependencies" -ForegroundColor Cyan
    if (-not (Test-Path "$root\ui\node_modules")) { npm --prefix "$root\ui" install }

    # The sync job uploads to the local API with the dev sync client; its secret is read here
    # from the dev SSM (needs your AWS credentials) and handed over.
    # 127.0.0.1, not localhost: on Windows localhost tries IPv6 first, which uvicorn does not
    # listen on, and Python's urllib waits about 2 s for that before every request.
    $env:LISTING_API_URL = "http://127.0.0.1:8000"
    $env:COGNITO_TOKEN_URL = $cognito.TokenUrl
    $env:COGNITO_CLIENT_ID = $cognito.SyncClientId
    $env:COGNITO_CLIENT_SECRET = Get-SsmSecret $cognito.SyncClientSecretParameter
    $env:COGNITO_SCOPE = "$($cognito.ScopePrefix)/create"
    $env:AWS_DEFAULT_REGION = "eu-central-1"
    Write-Host "==> Starting the sync job on http://localhost:9001 (local Lambda Invoke API)" -ForegroundColor Cyan
    $sync = Start-Process python -ArgumentList "-m", "pipenv", "run", "python", "-m", "local.local_lambda", "--port", "9001" `
        -WorkingDirectory "$root\syncJob\src" -NoNewWindow -PassThru

    # Local settings for the API: everything points at LocalStack. Inherited by the child process.
    $env:COGNITO_ISSUER = $cognito.Issuer
    $env:COGNITO_SCOPE_PREFIX = $cognito.ScopePrefix
    $env:TABLE_NAME = "Listings"
    $env:ALLOWED_ORIGINS = "http://localhost:$UiPort"
    $env:AWS_REGION = "eu-central-1"
    $env:AWS_DEFAULT_REGION = "eu-central-1"
    $env:AWS_ENDPOINT_URL = "http://localhost:4566"
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    # Scans go to the local sync job above instead of LocalStack (its free image has no container Lambdas).
    $env:SCAN_FUNCTION_NAME = "toaletka-sync-local"
    $env:AWS_ENDPOINT_URL_LAMBDA = "http://127.0.0.1:9001"

    # The UI signs in against the dev pool; .local files are not committed.
    @(
        "VITE_COGNITO_AUTHORITY=$($cognito.Issuer)"
        "VITE_COGNITO_CLIENT_ID=$($cognito.UiClientId)"
        "VITE_COGNITO_DOMAIN=$($cognito.DomainUrl)"
    ) | Set-Content -Encoding ascii "$root\ui\.env.development.local"

    Write-Host "==> Starting API on http://localhost:8000 (docs: /docs, needs a dev Cognito token)" -ForegroundColor Cyan
    $api = Start-Process python -ArgumentList "-m", "pipenv", "run", "uvicorn", "app.main:app", "--reload", "--port", "8000" `
        -WorkingDirectory "$root\listingApi" -NoNewWindow -PassThru

    Write-Host "==> Starting UI on http://localhost:$UiPort" -ForegroundColor Cyan
    npm --prefix "$root\ui" run dev -- --port $UiPort --strictPort
} finally {
    Write-Host "==> Stopping API, sync job and local dependencies" -ForegroundColor Cyan
    # /T also stops the uvicorn reloader's worker process and the sync job's browser.
    if ($api) { taskkill /T /F /PID $api.Id 2>&1 | Out-Null }
    if ($sync) { taskkill /T /F /PID $sync.Id 2>&1 | Out-Null }
    try { Invoke-Wsl "$compose down" } catch { Write-Warning $_ }
    Stop-Process -Id $wslKeepAlive.Id -ErrorAction SilentlyContinue
}
