#!/usr/bin/env bash
# Deploys the whole stack to AWS: Terraform infra, the API and sync images, and the React UI.
# Usage: ./scripts/deploy.sh --env dev|prod [--skip-images] [--skip-ui] [--yes] [--plan-only | --apply-plan]
#   --env           Environment: settings and AWS account from infra/environments/<env>.tfvars,
#                   state bucket and key from infra/environments/<env>.s3.tfbackend. Sign in to
#                   that account first, e.g. AWS_PROFILE=<profile> ./scripts/deploy.sh --env dev.
#   --skip-images   Keep the images the environment runs now; build and push nothing.
#   --skip-ui       Do not build and upload the UI.
#   --yes           Apply the Terraform plan without asking.
#   --plan-only     Build and push the images and write infra/tfplan; apply nothing.
#   --apply-plan    Apply an existing infra/tfplan, then deploy the UI. CI runs the two halves
#                   as separate jobs with an approval in between (.github/workflows/deploy.yml).
# Needs Terraform >= 1.10, Docker, the AWS CLI (signed in) and Node. See infra/README.md.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra="$root/infra"

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

case "$env" in
  dev|prod) ;;
  "") echo "Pass --env dev or --env prod." >&2; exit 1 ;;
  *) echo "Unknown environment: $env (expected dev or prod)" >&2; exit 1 ;;
esac
# Relative to infra/, where Terraform runs.
var_file="environments/$env.tfvars"
backend_file="environments/$env.s3.tfbackend"
plan="$infra/tfplan"

# terraform.tfvars is loaded for every environment, so a value in it would leak into both.
if [[ -f "$infra/terraform.tfvars" ]]; then
  echo "infra/terraform.tfvars applies to every environment. Move its settings into infra/$var_file" >&2
  echo "(image tags are no longer kept there) and delete it." >&2
  exit 1
fi

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
tf() { terraform -chdir="$infra" "$@"; }
tf_output() { tf output -raw "$1"; }
# Reads a string setting from a file under infra/, empty when missing.
setting() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\(.*\)\".*/\1/p" "$infra/$1" | head -n1
}

# In WSL, a tool missing on the Linux side resolves to the Windows one under /mnt/<drive>/,
# which does not understand Linux paths (e.g. npm then looks in the wrong folder).
require() {
  local path
  path="$(command -v "$1")" || { echo "$1 is not installed" >&2; exit 1; }
  if [[ "$path" == /mnt/* ]]; then
    echo "$1 resolves to the Windows binary $path. Install it inside WSL." >&2
    exit 1
  fi
}

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

# dev and prod live in separate accounts. Terraform checks this too (allowed_account_ids);
# checking here stops before any image is built or pushed to the wrong account.
step "Checking AWS credentials"
account="$(setting "$var_file" aws_account_id)"
# Captured first, so a failed call (signed out) stops the script under set -e.
identity="$(aws sts get-caller-identity --query '[Account, Arn]' --output text)"
read -r caller_account caller_arn <<<"$identity"
if [[ "$caller_account" != "$account" ]]; then
  echo "Signed in to account $caller_account, but $env lives in account $account ($var_file)." >&2
  echo "Sign in to the $env account, e.g. AWS_PROFILE=<$env profile> $0 --env $env" >&2
  exit 1
fi
echo "$caller_arn"

if $builds_images && [[ -n "$(git -C "$root" status --porcelain)" ]]; then
  echo "Warning: the working tree has uncommitted changes; image tags use the last commit's hash." >&2
fi

state_bucket="$(setting "$backend_file" bucket)"
state_key="$(setting "$backend_file" key)"
# modules/github_ci limits the CI roles to this environment's state.
export TF_VAR_state_bucket="$state_bucket" TF_VAR_state_key="$state_key"

step "Terraform init ($env: s3://$state_bucket/$state_key)"
# -reconfigure: infra/.terraform may still point at the other environment's state.
tf init -input=false -reconfigure -backend-config="$backend_file"

if ! tf fmt -check -recursive; then
  echo "The Terraform files listed above are not formatted. Run: terraform -chdir=infra fmt -recursive" >&2
  exit 1
fi
tf validate

name="$(setting "$var_file" name)"
region="$(setting "$var_file" region)"; region="${region:-eu-central-1}"

# Prints the tag of an image reference, or nothing for an empty or "None" answer.
image_tag() { [[ "$1" == *:* ]] && echo "${1##*:}"; return 0; }

# Sets api_tag and sync_tag to the images the environment runs now. They are read from AWS
# rather than a local file, which would go stale once CI deploys too.
read_running_tags() {
  api_tag="$(image_tag "$(aws lightsail get-container-services --region "$region" \
    --service-name "$name-listings-api" \
    --query 'containerServices[0].currentDeployment.containers.api.image' --output text 2>/dev/null || true)")"
  sync_tag="$(image_tag "$(aws lambda get-function --region "$region" --function-name "$name-sync" \
    --query 'Code.ImageUri' --output text 2>/dev/null || true)")"
}

# Builds and pushes both images, then sets api_tag and sync_tag to the new tag.
build_images() {
  # The images need the ECR repositories, which Terraform creates. They are missing on the
  # first deployment, or when deleted outside Terraform (the state then still lists them),
  # so ask AWS rather than the state. A targeted apply creates only the ECR resources;
  # the image tags do not matter for it. The API repository policy is left to the full apply:
  # it names the Lightsail service's pull role, so targeting it would create Lightsail too.
  # CI cannot do this (its plan role is read-only), so an environment's first deployment is local.
  if ! aws ecr describe-repositories --region "$region" \
      --repository-names "$name-listings-api" "$name-sync" >/dev/null 2>&1; then
    step "Creating the ECR repositories"
    local approve_flag=()
    $auto_approve && approve_flag=(-auto-approve)
    tf apply -input=false "${approve_flag[@]}" -var-file="$var_file" \
      -var api_image_tag= -var sync_image_tag= \
      -target=module.listing_api.aws_ecr_repository.api \
      -target=module.listing_api.aws_ecr_lifecycle_policy.api \
      -target=module.sync_job.aws_ecr_repository.sync \
      -target=module.sync_job.aws_ecr_lifecycle_policy.sync
  fi

  # Same tag scheme as scripts/build-image.ps1.
  local tag
  tag="$(git -C "$root" rev-parse --short HEAD)-$(date +%Y%m%d%H%M%S)"
  build_and_push listingApi toaletka-listings-api api_repository_url "$tag"
  build_and_push syncJob toaletka-sync sync_repository_url "$tag"
  api_tag="$tag"
  sync_tag="$tag"
}

# build_and_push <context dir> <local name> <repository output> <tag>
build_and_push() {
  local repo registry repo_region tag="$4"
  repo="$(tf_output "$3")"
  [[ -n "$repo" ]] || { echo "Terraform output $3 is empty; the ECR repository was not created." >&2; exit 1; }
  registry="${repo%%/*}"
  repo_region="$(cut -d. -f4 <<<"$registry")"

  step "Building $2:$tag"
  # Lambda and Lightsail run x86_64; Lambda also rejects multi-platform manifests, hence --provenance=false.
  docker build --platform linux/amd64 --provenance=false -t "$2:$tag" -t "$2:latest" "$root/$1"

  step "Pushing to $repo"
  aws ecr get-login-password --region "$repo_region" | docker login --username AWS --password-stdin "$registry"
  docker tag "$2:$tag" "$repo:$tag"
  # Pushes over a home connection sometimes time out. A retry only uploads the layers ECR does not have yet.
  local attempt
  for attempt in 1 2 3 4 5; do
    docker push "$repo:$tag" && return 0
    echo "Push failed (attempt $attempt of 5), retrying in $((attempt * 10))s..." >&2
    sleep $((attempt * 10))
  done
  echo "Push to $repo failed after 5 attempts." >&2
  exit 1
}

if [[ $phase != apply ]]; then
  if $skip_images; then read_running_tags; else build_images; fi
  if [[ -z "$api_tag" || -z "$sync_tag" ]]; then
    echo "$env runs no images yet. Run without --skip-images first." >&2
    exit 1
  fi

  step "Terraform plan ($env: api_image_tag=$api_tag, sync_image_tag=$sync_tag)"
  # The plan holds secrets from the state; it is kept only for --apply-plan.
  [[ $phase == all ]] && trap 'rm -f "$plan"' EXIT
  tf plan -input=false -out=tfplan -var-file="$var_file" \
    -var api_image_tag="$api_tag" -var sync_image_tag="$sync_tag"

  if [[ $phase == plan ]]; then
    step "Plan written to infra/tfplan"
    exit 0
  fi

  if ! $auto_approve; then
    read -r -p "Apply this plan to $env? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted; nothing applied."; exit 1; }
  fi
fi

step "Terraform apply ($env)"
tf apply -input=false tfplan
rm -f "$plan"

if $deploys_ui; then
  step "Building the UI"
  # CloudFront forwards /api/* to the Listings API, so the UI calls its own origin.
  # Process variables take precedence over ui/.env* files.
  npm --prefix "$root/ui" ci
  VITE_API_URL=/api VITE_API_KEY="$(tf_output api_key)" npm --prefix "$root/ui" run build

  step "Uploading the UI"
  aws s3 sync "$root/ui/dist" "s3://$(tf_output ui_bucket)" --delete
  aws cloudfront create-invalidation --distribution-id "$(tf_output ui_distribution_id)" --paths "/*" >/dev/null
fi

ui_url="$(tf_output ui_url)"
step "Smoke test"
if curl -fsS --max-time 15 "${ui_url%/}/api/health"; then
  echo
else
  echo "Warning: ${ui_url%/}/api/health did not answer; the Lightsail deployment may still be starting." >&2
fi

step "Done ($env)"
echo "UI:  $ui_url"
echo "API: $(tf_output api_url)"
