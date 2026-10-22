<#
.SYNOPSIS
  Runs the whole app locally: LocalStack (DynamoDB), the listings API and the UI.

.DESCRIPTION
  Usage: launch [-UiPort 5174]   (launch.cmd in the repo root calls this script)
  - Starts docker-compose.local-dependencies.yml through WSL (Docker is not installed on Windows).
  - Installs Python and npm dependencies when they are missing.
  - Runs the API on http://localhost:8000 and the UI on http://localhost:5173 (or -UiPort).
  - Sign-in and API tokens use the dev Cognito pool, so it needs AWS credentials for the dev account
    (reads the dev Terraform outputs, see cognito-settings.ps1).
  Ctrl+C stops everything, including LocalStack. The table is recreated empty on every launch; fill it with quickSync.
#>
param(
    # UI port; change it when 5173 is already taken.
    [int]$UiPort = 5173
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
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

try {
    Write-Host "==> Starting local dependencies (LocalStack) in WSL" -ForegroundColor Cyan
    Invoke-Wsl "$compose up -d --wait"

    Write-Host "==> Checking backend dependencies" -ForegroundColor Cyan
    $env:PIPENV_VENV_IN_PROJECT = "1"
    Push-Location "$root\listingApi"
    try {
        if (-not (Test-Path ".venv")) { python -m pipenv install --dev }
    } finally { Pop-Location }

    Write-Host "==> Checking UI dependencies" -ForegroundColor Cyan
    if (-not (Test-Path "$root\ui\node_modules")) { npm --prefix "$root\ui" install }

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
    Write-Host "==> Stopping API and local dependencies" -ForegroundColor Cyan
    # /T also stops the uvicorn reloader's worker process.
    if ($api) { taskkill /T /F /PID $api.Id 2>&1 | Out-Null }
    try { Invoke-Wsl "$compose down" } catch { Write-Warning $_ }
    Stop-Process -Id $wslKeepAlive.Id -ErrorAction SilentlyContinue
}
