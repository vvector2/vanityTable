#!/usr/bin/env bash
# Stops and removes the whole AWS environment: everything in the Terraform state, including the
# Listings table (all decisions), the Cognito user pool (and its UI user), the Lightsail service,
# the sync Lambda, CloudFront, the buckets and the ECR images. The counterpart of deploy.sh.
# Usage: ./scripts/nuke-env.sh [--state-bucket <bucket>] [--yes]
#   --state-bucket  Terraform state bucket (or TF_STATE_BUCKET). Needed only when infra/.terraform
#                   is not initialized yet.
#   --yes           Destroy without asking.
# The state bucket itself is kept, so ./scripts/deploy.sh can build the environment again.
# Needs Terraform >= 1.10 and the AWS CLI (signed in). See infra/README.md.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra="$root/infra"
tfvars="$infra/terraform.tfvars"

state_bucket="${TF_STATE_BUCKET:-}"
auto_approve=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-bucket) state_bucket="$2"; shift 2 ;;
    --yes|-y) auto_approve=true; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
tf() { terraform -chdir="$infra" "$@"; }
# Reads a string variable from terraform.tfvars, empty when missing.
tfvars_get() {
  [[ -f "$tfvars" ]] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\(.*\)\".*/\1/p" "$tfvars" | head -n1
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

step "Checking AWS credentials"
aws sts get-caller-identity --query Arn --output text

step "Terraform init"
if [[ -d "$infra/.terraform" && -z "$state_bucket" ]]; then
  tf init -input=false
elif [[ -n "$state_bucket" ]]; then
  tf init -input=false -backend-config="bucket=$state_bucket"
else
  echo "Terraform is not initialized. Pass --state-bucket <bucket> or set TF_STATE_BUCKET." >&2
  exit 1
fi

if [[ -z "$(tf state list)" ]]; then
  echo "The Terraform state is empty; nothing to remove."
  exit 0
fi

name="$(tfvars_get name)"; name="${name:-toaletka}"
region="$(tfvars_get region)"; region="${region:-eu-central-1}"

# Destroy ignores the image tags, but the variables have no default.
step "Terraform destroy plan"
plan="$infra/tfplan"
trap 'rm -f "$plan"' EXIT
tf plan -destroy -input=false -out=tfplan \
  -var api_image_tag="$(tfvars_get api_image_tag)" -var sync_image_tag="$(tfvars_get sync_image_tag)"

if ! $auto_approve; then
  echo
  echo "This permanently deletes the '$name' environment, including every accepted and rejected"
  echo "listing in the Listings table and the Cognito UI user. It cannot be undone."
  read -r -p "Type the environment name ($name) to continue: " answer
  [[ "$answer" == "$name" ]] || { echo "Aborted; nothing removed."; exit 1; }
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
step "Terraform destroy"
tf apply -input=false tfplan

# The images are gone with the ECR repositories, so the old tags would break deploy.sh --skip-images.
if [[ -f "$tfvars" ]]; then
  sed -i.bak -E '/^[[:space:]]*(api_image_tag|sync_image_tag)[[:space:]]*=/d' "$tfvars" && rm -f "$tfvars.bak"
fi

step "Done"
echo "The '$name' environment is removed. The state bucket is kept; ./scripts/deploy.sh rebuilds everything."
