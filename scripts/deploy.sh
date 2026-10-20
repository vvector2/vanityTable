#!/usr/bin/env bash
# Deploys the whole stack to AWS: Terraform infra, the API and sync images, and the React UI.
# Usage: ./scripts/deploy.sh [--state-bucket <bucket>] [--skip-images] [--skip-ui] [--yes]
#   --state-bucket  Terraform state bucket (or TF_STATE_BUCKET). Needed only when infra/.terraform
#                   is not initialized yet.
#   --skip-images   Keep the image tags already in infra/terraform.tfvars; build and push nothing.
#   --skip-ui       Do not build and upload the UI.
#   --yes           Apply the Terraform plan without asking.
# Needs Terraform >= 1.10, Docker, the AWS CLI (signed in) and Node. See infra/README.md.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
infra="$root/infra"
tfvars="$infra/terraform.tfvars"

state_bucket="${TF_STATE_BUCKET:-}"
skip_images=false
skip_ui=false
auto_approve=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-bucket) state_bucket="$2"; shift 2 ;;
    --skip-images) skip_images=true; shift ;;
    --skip-ui) skip_ui=true; shift ;;
    --yes|-y) auto_approve=true; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
tf() { terraform -chdir="$infra" "$@"; }
tf_output() { tf output -raw "$1"; }
# Reads a string variable from terraform.tfvars, empty when missing.
tfvars_get() {
  [[ -f "$tfvars" ]] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\(.*\)\".*/\1/p" "$tfvars" | head -n1
}

# Sets a string variable in terraform.tfvars, so a later plain `terraform apply` keeps the same images.
tfvars_set() {
  touch "$tfvars"
  if grep -qE "^[[:space:]]*$1[[:space:]]*=" "$tfvars"; then
    sed -i.bak -E "s|^[[:space:]]*$1[[:space:]]*=.*|$1 = \"$2\"|" "$tfvars" && rm -f "$tfvars.bak"
  else
    printf '%s = "%s"\n' "$1" "$2" >> "$tfvars"
  fi
  # Aligns the `=` signs, so `terraform fmt -check` passes on the next run.
  tf fmt terraform.tfvars >/dev/null
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

require terraform
require aws
if ! $skip_images; then require docker; fi
if ! $skip_ui; then require npm; fi

step "Checking AWS credentials"
aws sts get-caller-identity --query Arn --output text

if [[ -n "$(git -C "$root" status --porcelain)" ]]; then
  echo "Warning: the working tree has uncommitted changes; image tags use the last commit's hash." >&2
fi

step "Terraform init"
if [[ -d "$infra/.terraform" && -z "$state_bucket" ]]; then
  tf init -input=false
elif [[ -n "$state_bucket" ]]; then
  tf init -input=false -backend-config="bucket=$state_bucket"
else
  echo "Terraform is not initialized. Pass --state-bucket <bucket> or set TF_STATE_BUCKET." >&2
  exit 1
fi

# terraform.tfvars is partly written by this script, so format it rather than fail on it.
[[ -f "$tfvars" ]] && tf fmt terraform.tfvars >/dev/null
if ! tf fmt -check -recursive; then
  echo "The Terraform files listed above are not formatted. Run: terraform -chdir=infra fmt -recursive" >&2
  exit 1
fi
tf validate

api_tag="$(tfvars_get api_image_tag)"
sync_tag="$(tfvars_get sync_image_tag)"

if ! $skip_images; then
  # The images need the ECR repositories, which Terraform creates. They are missing on the
  # first deployment, or when deleted outside Terraform (the state then still lists them),
  # so ask AWS rather than the state. A targeted apply creates only the ECR resources;
  # the image tags do not matter for it. The API repository policy is left to the full apply:
  # it names the Lightsail service's pull role, so targeting it would create Lightsail too.
  name="$(tfvars_get name)"; name="${name:-toaletka}"
  region="$(tfvars_get region)"; region="${region:-eu-central-1}"
  if ! aws ecr describe-repositories --region "$region" \
      --repository-names "$name-listings-api" "$name-sync" >/dev/null 2>&1; then
    step "Creating the ECR repositories"
    approve_flag=()
    $auto_approve && approve_flag=(-auto-approve)
    tf apply -input=false "${approve_flag[@]}" \
      -var api_image_tag="$api_tag" -var sync_image_tag="$sync_tag" \
      -target=module.listing_api.aws_ecr_repository.api \
      -target=module.listing_api.aws_ecr_lifecycle_policy.api \
      -target=module.sync_job.aws_ecr_repository.sync \
      -target=module.sync_job.aws_ecr_lifecycle_policy.sync
  fi

  # Same tag scheme as scripts/build-image.ps1.
  tag="$(git -C "$root" rev-parse --short HEAD)-$(date +%Y%m%d%H%M%S)"

  # build_and_push <context dir> <local name> <repository output>
  build_and_push() {
    local repo registry region
    repo="$(tf_output "$3")"
    [[ -n "$repo" ]] || { echo "Terraform output $3 is empty; the ECR repository was not created." >&2; exit 1; }
    registry="${repo%%/*}"
    region="$(cut -d. -f4 <<<"$registry")"

    step "Building $2:$tag"
    # Lambda and Lightsail run x86_64; Lambda also rejects multi-platform manifests, hence --provenance=false.
    docker build --platform linux/amd64 --provenance=false -t "$2:$tag" -t "$2:latest" "$root/$1"

    step "Pushing to $repo"
    aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
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

  build_and_push listingApi toaletka-listings-api api_repository_url
  build_and_push syncJob toaletka-sync sync_repository_url
  api_tag="$tag"
  sync_tag="$tag"
fi

if [[ -z "$api_tag" || -z "$sync_tag" ]]; then
  echo "No image tags in $tfvars. Run without --skip-images first." >&2
  exit 1
fi

step "Terraform plan (api_image_tag=$api_tag, sync_image_tag=$sync_tag)"
plan="$infra/tfplan"
trap 'rm -f "$plan"' EXIT
tf plan -input=false -out=tfplan -var api_image_tag="$api_tag" -var sync_image_tag="$sync_tag"

if ! $auto_approve; then
  read -r -p "Apply this plan? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted; nothing applied."; exit 1; }
fi

step "Terraform apply"
tf apply -input=false tfplan
tfvars_set api_image_tag "$api_tag"
tfvars_set sync_image_tag "$sync_tag"

if ! $skip_ui; then
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

step "Done"
echo "UI:  $ui_url"
echo "API: $(tf_output api_url)"
