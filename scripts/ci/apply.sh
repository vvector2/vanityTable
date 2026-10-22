#!/usr/bin/env bash
# Apply job of .github/workflows/deploy.yml, after approval. Applies infra/tfplan written by
# scripts/ci/plan.sh on the same commit, deploys the UI and calls /api/health. Never prompts.
# Usage: ./scripts/ci/apply.sh dev|prod
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/deploy-common.sh"

use_env "${1:-}"
require terraform
require aws
require npm

check_account
tf_init
tf_apply_plan
deploy_ui
smoke_test
