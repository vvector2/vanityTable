<#
.SYNOPSIS
  Reads the Cognito settings of one environment from its Terraform state.

.DESCRIPTION
  Dot-source it, then call Get-CognitoSettings -Env dev (and Get-SsmSecret for client secrets). Used by launch.ps1, quick-sync.ps1
  and admin-token.ps1. Re-initializes infra/ for that environment's state bucket (like
  deploy.sh), so it needs AWS credentials for that environment's account.
#>

# Reads an SSM SecureString with the AWS CLI. The CLI understands every credential source,
# `aws login` included, which boto3 cannot use without botocore[crt].
function Get-SsmSecret([string]$Name) {
    $value = aws ssm get-parameter --region eu-central-1 --name $Name --with-decryption --query Parameter.Value --output text
    if ($LASTEXITCODE -ne 0) { throw "Could not read $Name from SSM" }
    return $value
}

function Get-CognitoSettings([ValidateSet("dev", "prod")][string]$Env = "dev") {
    $infra = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "infra"
    terraform -chdir="$infra" init -input=false -reconfigure "-backend-config=environments/$Env.s3.tfbackend" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "terraform init for $Env failed (signed in to the $Env account?)" }

    $outputs = terraform -chdir="$infra" output -json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Could not read Terraform outputs for $Env" }
    function Value([string]$name) {
        $output = $outputs.$name
        if ($null -eq $output) { throw "Terraform output $name is missing; apply $Env first" }
        return $output.value
    }
    # Only admin-token.ps1 needs these, so a state applied before they existed still works for the rest.
    function Optional([string]$name) { if ($outputs.$name) { $outputs.$name.value } }

    return @{
        Issuer                     = Value "cognito_issuer"
        DomainUrl                  = Value "cognito_domain_url"
        TokenUrl                   = Value "cognito_token_url"
        ScopePrefix                = Value "listings_scope_prefix"
        UiClientId                 = Value "cognito_ui_client_id"
        SyncClientId               = Value "sync_cognito_client_id"
        SyncClientSecretParameter  = Value "sync_cognito_client_secret_parameter"
        AdminClientId              = Optional "cognito_admin_client_id"
        AdminClientSecretParameter = Optional "cognito_admin_client_secret_parameter"
    }
}
