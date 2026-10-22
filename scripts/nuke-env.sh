#!/usr/bin/env bash
# Stops and removes one whole AWS environment: everything in its Terraform state, including the
# Listings table (all decisions), the Cognito user pool (and its UI user), the Lightsail service,
# the sync Lambda, CloudFront, the buckets and the ECR images. The counterpart of deploy.sh.
# Usage: ./scripts/nuke-env.sh --env dev|prod [--yes]
#   --env  Environment: settings and AWS account from infra/environments/<env>.tfvars, state bucket
#          and key from infra/environments/<env>.s3.tfbackend. Sign in to that account first.
#   --yes  Destroy without asking.
# The state bucket itself is kept, so ./scripts/deploy.sh can build the environment again.
# Needs Terraform >= 1.10 and the AWS CLI (signed in). See infra/README.md.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra="$root/infra"

env=""
auto_approve=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) env="$2"; shift 2 ;;
    --yes|-y) auto_approve=true; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$env" in
  dev|prod) ;;
  "") echo "Pass --env dev or --env prod." >&2; exit 1 ;;
  *) echo "Unknown environment: $env (expected dev or prod)" >&2; exit 1 ;;
esac
# Relative to infra/, where Terraform runs.
var_file="environments/$env.tfvars"
backend_file="environments/$env.s3.tfbackend"

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
tf() { terraform -chdir="$infra" "$@"; }
# Reads a string setting from a file under infra/, empty when missing.
setting() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\(.*\)\".*/\1/p" "$infra/$1" | head -n1
}
# Reads a top-level attribute of a resource in the state, empty when the resource is not there.
state_attr() {
  tf state show -no-color "$1" 2>/dev/null \
    | sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\(.*\)\"$/\1/p" | head -n1
}

# Same WSL check as deploy.sh: a Windows binary under /mnt/<drive>/ does not understand Linux paths.
require() {
  local path
  path="$(command -v "$1")" || { echo "$1 is not installed" >&2; exit 1; }
  if [[ "$path" == /mnt/* ]]; then
    echo "$1 resolves to the Windows binary $path. Install it inside WSL." >&2
    exit 1
  fi
}

require terraform
require aws

# Same account check as deploy.sh: never destroy one environment from the other's account.
step "Checking AWS credentials"
account="$(setting "$var_file" aws_account_id)"
identity="$(aws sts get-caller-identity --query '[Account, Arn]' --output text)"
read -r caller_account caller_arn <<<"$identity"
if [[ "$caller_account" != "$account" ]]; then
  echo "Signed in to account $caller_account, but $env lives in account $account ($var_file)." >&2
  echo "Sign in to the $env account, e.g. AWS_PROFILE=<$env profile> $0 --env $env" >&2
  exit 1
fi
echo "$caller_arn"

step "Terraform init ($env: s3://$(setting "$backend_file" bucket)/$(setting "$backend_file" key))"
# -reconfigure: infra/.terraform may still point at the other environment's state.
tf init -input=false -reconfigure -backend-config="$backend_file"

if [[ -z "$(tf state list)" ]]; then
  echo "The $env Terraform state is empty; nothing to remove."
  exit 0
fi

name="$(setting "$var_file" name)"
region="$(setting "$var_file" region)"; region="${region:-eu-central-1}"

# Destroy ignores the image tags, but the variables have no default.
step "Terraform destroy plan ($env)"
plan="$infra/tfplan"
trap 'rm -f "$plan"' EXIT
tf plan -destroy -input=false -out=tfplan -var-file="$var_file" -var api_image_tag= -var sync_image_tag=

if ! $auto_approve; then
  echo
  echo "This permanently deletes the $env environment ('$name' in account $account), including every"
  echo "accepted and rejected listing in the Listings table and the Cognito UI user. It cannot be undone."
  read -r -p "Type the environment name ($env) to continue: " answer
  [[ "$answer" == "$env" ]] || { echo "Aborted; nothing removed."; exit 1; }
fi

# The table and the user pool are protected against deletion (modules/common), so Terraform
# cannot remove them until the protection is off. Done with the AWS CLI so the Terraform code
# keeps the protection for every other apply.
step "Turning off deletion protection"
table="$(state_attr module.common.aws_dynamodb_table.listings name)"
if [[ -n "$table" ]]; then
  aws dynamodb update-table --region "$region" --table-name "$table" \
    --no-deletion-protection-enabled >/dev/null
  aws dynamodb wait table-exists --region "$region" --table-name "$table"
  echo "DynamoDB table $table"
fi
pool="$(state_attr module.common.aws_cognito_user_pool.main id)"
if [[ -n "$pool" ]]; then
  # update-user-pool resets every setting it is not given; harmless here, the pool is deleted next.
  aws cognito-idp update-user-pool --region "$region" --user-pool-id "$pool" \
    --deletion-protection INACTIVE
  echo "Cognito user pool $pool"
fi

# CloudFront and Lightsail take several minutes to delete.
step "Terraform destroy ($env)"
tf apply -input=false tfplan

step "Done"
echo "The $env environment is removed. The state bucket is kept; ./scripts/deploy.sh --env $env rebuilds everything."
