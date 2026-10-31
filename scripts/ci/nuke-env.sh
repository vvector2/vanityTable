#!/usr/bin/env bash
# Stops and removes one whole AWS environment: everything in its Terraform state, including the
# Listings table (all decisions), the Cognito user pool (and its UI user), the Lightsail service,
# the sync Lambda, CloudFront, the buckets and the ECR images. The counterpart of deploy.sh.
# Usage: ./scripts/ci/nuke-env.sh --env dev|prod [--yes]
#   --env  Environment: settings and AWS account from infra/environments/<env>.tfvars, state bucket
#          and key from infra/environments/<env>.s3.tfbackend. Sign in to that account first.
#   --yes  Destroy without asking. Required in GitHub Actions, which has no terminal to answer.
# The state bucket itself is kept, so ./scripts/local/deploy.sh can build the environment again.
# GitHub Actions runs it with --yes from the "Destroy environment" workflow (destroy.yml).
# Needs Terraform >= 1.10 and the AWS CLI (signed in). See infra/README.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/deploy-common.sh"

env=""
auto_approve=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) env="$2"; shift 2 ;;
    --yes|-y) auto_approve=true; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

use_env "$env"

require terraform
require aws

# Never destroy one environment from the other's account.
if ! check_account; then
  echo "Sign in to the $env account, e.g. AWS_PROFILE=<$env profile> $0 --env $env" >&2
  exit 1
fi

tf_init

if state_empty; then
  echo "The $env Terraform state is empty; nothing to remove."
  exit 0
fi

trap 'rm -f "$plan"' EXIT
tf_plan_destroy
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Terraform destroy: $env"
    echo '```'
    tf show -no-color tfplan | grep -E '^Plan:|^No changes' || true
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

if ! $auto_approve; then
  echo
  echo "This permanently deletes the $env environment ('$name' in account $account), including every"
  echo "accepted and rejected listing in the Listings table and the Cognito UI user. It cannot be undone."
  read -r -p "Type the environment name ($env) to continue: " answer
  [[ "$answer" == "$env" ]] || { echo "Aborted; nothing removed."; exit 1; }
fi

tf_destroy

step "Done"
echo "The $env environment is removed. The state bucket is kept; ./scripts/local/deploy.sh --env $env rebuilds everything."
