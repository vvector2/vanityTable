#!/usr/bin/env bash
# Plan job of .github/workflows/deploy.yml. Builds and pushes both images and writes infra/tfplan;
# in GitHub Actions it also writes the resource changes to the run summary. Never prompts: on an
# environment's first run it creates the ECR repositories (empty) without asking.
# Usage: ./scripts/ci/plan.sh dev|prod
# For a deploy from your machine use scripts/local/deploy.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/deploy-common.sh"

use_env "${1:-}"
require terraform
require aws
require docker

check_no_shared_tfvars
check_account
tf_init
tf_check
ensure_ecr_repositories true
build_images
tf_plan

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Terraform plan: $env at \`$(git -C "$root" rev-parse HEAD)\`"
    echo '```'
    tf show -no-color tfplan | grep -E '^ *# |^Plan:|^No changes' || true
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
step "Plan written to infra/tfplan"
