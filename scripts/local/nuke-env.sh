#!/usr/bin/env bash
# Stops and removes one whole AWS environment: everything in its Terraform state, including the
# Listings table (all decisions), the Cognito user pool (and its UI user), the Lightsail service,
# the sync Lambda, CloudFront, the buckets and the ECR images. The counterpart of deploy.sh.
# Usage: ./scripts/local/nuke-env.sh --env dev|prod [--yes]
#   --env  Environment: settings and AWS account from infra/environments/<env>.tfvars, state bucket
#          and key from infra/environments/<env>.s3.tfbackend. Sign in to that account first.
#   --yes  Destroy without asking.
# The state bucket itself is kept, so ./scripts/local/deploy.sh can build the environment again.
# Needs Terraform >= 1.10 and the AWS CLI (signed in). See infra/README.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/deploy-common.sh"

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

use_env "$env"

# Reads a top-level attribute of a resource in the state, empty when the resource is not there.
state_attr() {
  tf state show -no-color "$1" 2>/dev/null \
    | sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\(.*\)\"$/\1/p" | head -n1
}

require terraform
require aws

# Never destroy one environment from the other's account.
if ! check_account; then
  echo "Sign in to the $env account, e.g. AWS_PROFILE=<$env profile> $0 --env $env" >&2
  exit 1
fi

tf_init

if [[ -z "$(tf state list)" ]]; then
  echo "The $env Terraform state is empty; nothing to remove."
  exit 0
fi

# Destroy ignores the image tags, but the variables have no default.
step "Terraform destroy plan ($env)"
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
echo "The $env environment is removed. The state bucket is kept; ./scripts/local/deploy.sh --env $env rebuilds everything."
