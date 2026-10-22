#!/usr/bin/env bash
# Deploys the whole stack from your machine: Terraform infra, the API and sync images, and the UI.
# CI uses scripts/ci/plan.sh and scripts/ci/apply.sh instead.
# Usage: ./scripts/local/deploy.sh --env dev|prod [--skip-images] [--skip-ui] [--yes] [--plan-only | --apply-plan]
#   --env           Environment: settings and AWS account from infra/environments/<env>.tfvars,
#                   state bucket and key from infra/environments/<env>.s3.tfbackend. Sign in to
#                   that account first, e.g. AWS_PROFILE=<profile> ./scripts/local/deploy.sh --env dev.
#   --skip-images   Keep the images the environment runs now; build and push nothing.
#   --skip-ui       Do not build and upload the UI.
#   --yes           Apply without asking.
#   --plan-only     Build and push the images and write infra/tfplan; apply nothing.
#   --apply-plan    Apply an existing infra/tfplan, then deploy the UI.
# Needs Terraform >= 1.10, Docker, the AWS CLI (signed in) and Node, from WSL or Linux. See infra/README.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/deploy-common.sh"

env=""
skip_images=false
skip_ui=false
auto_approve=false
phase=all

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) env="$2"; shift 2 ;;
    --skip-images) skip_images=true; shift ;;
    --skip-ui) skip_ui=true; shift ;;
    --yes|-y) auto_approve=true; shift ;;
    --plan-only) phase=plan; shift ;;
    --apply-plan) phase=apply; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

use_env "$env"
check_no_shared_tfvars

builds_images=false
[[ $phase != apply ]] && ! $skip_images && builds_images=true
deploys_ui=false
[[ $phase != plan ]] && ! $skip_ui && deploys_ui=true

require terraform
require aws
if $builds_images; then require docker; fi
if $deploys_ui; then require npm; fi

if [[ $phase == apply && ! -f "$plan" ]]; then
  echo "No infra/tfplan to apply. Run with --plan-only first." >&2
  exit 1
fi

if ! check_account; then
  echo "Sign in to the $env account, e.g. AWS_PROFILE=<$env profile> $0 --env $env" >&2
  exit 1
fi

if $builds_images && [[ -n "$(git -C "$root" status --porcelain)" ]]; then
  echo "Warning: the working tree has uncommitted changes; image tags use the last commit's hash." >&2
fi

tf_init
tf_check

if [[ $phase != apply ]]; then
  if $skip_images; then
    read_running_tags
  else
    ensure_ecr_repositories "$auto_approve"
    build_images
  fi

  # The plan holds secrets from the state; it is kept only for --apply-plan.
  [[ $phase == all ]] && trap 'rm -f "$plan"' EXIT
  tf_plan

  if [[ $phase == plan ]]; then
    step "Plan written to infra/tfplan"
    exit 0
  fi

  if ! $auto_approve; then
    read -r -p "Apply this plan to $env? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted; nothing applied."; exit 1; }
  fi
fi

tf_apply_plan
if $deploys_ui; then deploy_ui; fi
smoke_test
