<#
.SYNOPSIS
  Prints an access token with the listings/admin scope, for DELETE /listings/{id}.

.DESCRIPTION
  Usage: ./scripts/local/admin-token.ps1 [-Env dev|prod]
  Uses the admin machine client (client credentials). Needs AWS credentials for that
  environment's account: the client ID comes from Terraform and the secret from SSM
  (SecureString). Set COGNITO_ADMIN_CLIENT_SECRET to use another secret instead. Example:
    $token = ./scripts/local/admin-token.ps1
    curl.exe -X DELETE -H "Authorization: Bearer $token" <ui_url>/api/listings/<id>
#>
param(
    [ValidateSet("dev", "prod")][string]$Env = "dev"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\cognito-settings.ps1"
$cognito = Get-CognitoSettings -Env $Env

$secret = $env:COGNITO_ADMIN_CLIENT_SECRET
if (-not $secret) {
    $secret = aws ssm get-parameter --region eu-central-1 --name $cognito.AdminClientSecretParameter `
        --with-decryption --query Parameter.Value --output text
    if ($LASTEXITCODE -ne 0) { throw "Could not read $($cognito.AdminClientSecretParameter) from SSM" }
}

$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($cognito.AdminClientId):$secret"))
$response = Invoke-RestMethod -Method Post -Uri $cognito.TokenUrl `
    -Headers @{ Authorization = "Basic $basic" } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{ grant_type = "client_credentials"; scope = "$($cognito.ScopePrefix)/admin" }
$response.access_token
