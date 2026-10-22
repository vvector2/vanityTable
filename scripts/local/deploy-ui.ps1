# Builds the React UI, uploads it to the UI bucket and invalidates CloudFront.
# Usage: ./scripts/local/deploy-ui.ps1
# Needs Node, the AWS CLI and an applied Terraform state (reads its outputs).
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Get-TerraformOutput([string]$Name) {
    $value = terraform -chdir="$root/infra" output -raw $Name
    if ($LASTEXITCODE -ne 0) { throw "Could not read $Name from Terraform" }
    return $value
}

$bucket = Get-TerraformOutput "ui_bucket"
$distribution = Get-TerraformOutput "ui_distribution_id"

# CloudFront forwards /api/* to the Listings API, so the UI calls its own origin.
# Process variables take precedence over ui/.env* files.
$env:VITE_API_URL = "/api"
$env:VITE_COGNITO_AUTHORITY = Get-TerraformOutput "cognito_issuer"
$env:VITE_COGNITO_CLIENT_ID = Get-TerraformOutput "cognito_ui_client_id"
$env:VITE_COGNITO_DOMAIN = Get-TerraformOutput "cognito_domain_url"
try {
    npm --prefix "$root/ui" ci
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
    npm --prefix "$root/ui" run build
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
}
finally {
    Remove-Item Env:VITE_API_URL, Env:VITE_COGNITO_AUTHORITY, Env:VITE_COGNITO_CLIENT_ID, Env:VITE_COGNITO_DOMAIN -ErrorAction SilentlyContinue
}

aws s3 sync "$root/ui/dist" "s3://$bucket" --delete
if ($LASTEXITCODE -ne 0) { throw "s3 sync failed" }
aws cloudfront create-invalidation --distribution-id $distribution --paths "/*" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "CloudFront invalidation failed" }

Write-Host "Deployed to $(Get-TerraformOutput 'ui_url')"
