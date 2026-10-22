<#
.SYNOPSIS
  Prints an access token with the listings/admin scope, for DELETE /listings/{id}.

.DESCRIPTION
  Usage: ./scripts/admin-token.ps1 [-Env dev|prod]
  Uses the admin machine client (client credentials). Needs AWS credentials for that
  environment's account. Example:
    $token = ./scripts/admin-token.ps1
    curl.exe -X DELETE -H "Authorization: Bearer $token" <ui_url>/api/listings/<id>
#>
param(
    [ValidateSet("dev", "prod")][string]$Env = "dev"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\cognito-settings.ps1"
$cognito = Get-CognitoSettings -Env $Env

$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($cognito.AdminClientId):$($cognito.AdminClientSecret)"))
$response = Invoke-RestMethod -Method Post -Uri $cognito.TokenUrl `
    -Headers @{ Authorization = "Basic $basic" } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{ grant_type = "client_credentials"; scope = "$($cognito.ScopePrefix)/admin" }
$response.access_token
