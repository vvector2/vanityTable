#!/usr/bin/env bash
# Prints the commit and the AWS role of one environment as GitHub step outputs (sha=..., role=...).
# Each environment has its own AWS account, named in its tfvars; the role is created by hand in
# that account as github-actions-<env> (infra/README.md, section CI/CD). Needs no AWS credentials.
# Usage: ./scripts/ci/resolve-role.sh dev|prod >> "$GITHUB_OUTPUT"
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/deploy-common.sh"

use_env "${1:-}"
[[ "$account" =~ ^[0-9]{12}$ ]] || { echo "No aws_account_id in infra/$var_file" >&2; exit 1; }
echo "sha=$(git -C "$root" rev-parse HEAD)"
echo "role=arn:aws:iam::$account:role/github-actions-$env"
