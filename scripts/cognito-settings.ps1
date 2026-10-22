<#
.SYNOPSIS
  Reads the Cognito settings of one environment from its Terraform state.

.DESCRIPTION
  Dot-source it, then call Get-CognitoSettings -Env dev. Used by launch.ps1, quick-sync.ps1
  and admin-token.ps1. Re-initializes infra/ for that environment's state bucket (like
  deploy.sh), so it needs AWS credentials for that environment's account.
#>

function Get-CognitoSettings([ValidateSet("dev", "prod")][string]$Env = "dev") {
    $infra = Join-Path (Split-Path $PSScriptRoot -Parent) "infra"
    terraform -chdir="$infra" init -input=false -reconfigure "-backend-config=environments/$Env.s3.tfbackend" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "terraform init for $Env failed (signed in to the $Env account?)" }

    $outputs = terraform -chdir="$infra" output -json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Could not read Terraform outputs for $Env" }
    function Value([string]$name) {
        $output = $outputs.$name
        if ($null -eq $output) { throw "Terraform output $name is missing; apply $Env first" }
        return $output.value
    }

    return @{
        Issuer                     = Value "cognito_issuer"
        DomainUrl                  = Value "cognito_domain_url"
        TokenUrl                   = Value "cognito_token_url"
        ScopePrefix                = Value "listings_scope_prefix"
        UiClientId                 = Value "cognito_ui_client_id"
        SyncClientId               = Value "sync_cognito_client_id"
        SyncClientSecretParameter  = Value "sync_cognito_client_secret_parameter"
        AdminClientId              = Value "cognito_admin_client_id"
        AdminClientSecret          = Value "cognito_admin_client_secret"
    }
}
