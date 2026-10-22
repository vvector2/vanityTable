# Deploy steps shared by the local scripts (scripts/local/deploy.sh, nuke-env.sh) and the
# pipeline scripts (scripts/ci/*.sh). Not run directly: source it, then call use_env <env>.
# Callers run with set -euo pipefail.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
infra="$root/infra"

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

# use_env <env>: checks the name and sets env, var_file, backend_file, plan, account, name, region.
use_env() {
  env="$1"
  case "$env" in
    dev|prod) ;;
    "") echo "Pass the environment: dev or prod." >&2; exit 1 ;;
    *) echo "Unknown environment: $env (expected dev or prod)" >&2; exit 1 ;;
  esac
  # Relative to infra/, where Terraform runs.
  var_file="environments/$env.tfvars"
  backend_file="environments/$env.s3.tfbackend"
  plan="$infra/tfplan"
  account="$(setting "$var_file" aws_account_id)"
  name="$(setting "$var_file" name)"
  region="$(setting "$var_file" region)"; region="${region:-eu-central-1}"
}

# terraform.tfvars is loaded for every environment, so a value in it would leak into both.
check_no_shared_tfvars() {
  if [[ -f "$infra/terraform.tfvars" ]]; then
    echo "infra/terraform.tfvars applies to every environment. Move its settings into infra/$var_file" >&2
    echo "(image tags are no longer kept there) and delete it." >&2
    exit 1
  fi
}

# dev and prod live in separate accounts. Terraform checks this too (allowed_account_ids);
# checking first stops before any image is built or pushed to the wrong account.
check_account() {
  step "Checking AWS credentials"
  local identity caller_account caller_arn
  # Captured first, so a failed call (signed out) stops the script under set -e.
  identity="$(aws sts get-caller-identity --query '[Account, Arn]' --output text)"
  read -r caller_account caller_arn <<<"$identity"
  if [[ "$caller_account" != "$account" ]]; then
    echo "Signed in to account ${caller_account:-<none>}, but $env lives in account $account ($var_file)." >&2
    # return, not exit: the local scripts add a sign-in hint. Under set -e a bare call still stops.
    return 1
  fi
  echo "$caller_arn"
}

tf_init() {
  step "Terraform init ($env: s3://$(setting "$backend_file" bucket)/$(setting "$backend_file" key))"
  # -reconfigure: infra/.terraform may still point at the other environment's state.
  tf init -input=false -reconfigure -backend-config="$backend_file"
}

tf_check() {
  if ! tf fmt -check -recursive; then
    echo "The Terraform files listed above are not formatted. Run: terraform -chdir=infra fmt -recursive" >&2
    exit 1
  fi
  tf validate
}

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

# ensure_ecr_repositories <auto approve: true|false>
# The images need the ECR repositories, which Terraform creates. They are missing on the
# first deployment, or when deleted outside Terraform (the state then still lists them),
# so ask AWS rather than the state. A targeted apply creates only the ECR resources;
# the image tags do not matter for it. The API repository policy is left to the full apply:
# it names the Lightsail service's pull role, so targeting it would create Lightsail too.
ensure_ecr_repositories() {
  if aws ecr describe-repositories --region "$region" \
      --repository-names "$name-listings-api" "$name-sync" >/dev/null 2>&1; then
    return 0
  fi
  step "Creating the ECR repositories"
  local approve_flag=()
  $1 && approve_flag=(-auto-approve)
  tf apply -input=false "${approve_flag[@]}" -var-file="$var_file" \
    -var api_image_tag= -var sync_image_tag= \
    -target=module.listing_api.aws_ecr_repository.api \
    -target=module.listing_api.aws_ecr_lifecycle_policy.api \
    -target=module.sync_job.aws_ecr_repository.sync \
    -target=module.sync_job.aws_ecr_lifecycle_policy.sync
}

# Builds and pushes both images, then sets api_tag and sync_tag to the new tag.
build_images() {
  # Same tag scheme as scripts/local/build-image.ps1.
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

# Writes infra/tfplan for api_tag and sync_tag. The plan holds secrets from the state.
tf_plan() {
  if [[ -z "${api_tag:-}" || -z "${sync_tag:-}" ]]; then
    echo "$env runs no images yet. Build them first." >&2
    exit 1
  fi
  step "Terraform plan ($env: api_image_tag=$api_tag, sync_image_tag=$sync_tag)"
  tf plan -input=false -out=tfplan -var-file="$var_file" \
    -var api_image_tag="$api_tag" -var sync_image_tag="$sync_tag"
}

tf_apply_plan() {
  if [[ ! -f "$plan" ]]; then
    echo "No infra/tfplan to apply. Plan first." >&2
    exit 1
  fi
  step "Terraform apply ($env)"
  tf apply -input=false tfplan
  rm -f "$plan"
}

deploy_ui() {
  step "Building the UI"
  # CloudFront forwards /api/* to the Listings API, so the UI calls its own origin.
  # Process variables take precedence over ui/.env* files.
  npm --prefix "$root/ui" ci
  VITE_API_URL=/api \
    VITE_COGNITO_AUTHORITY="$(tf_output cognito_issuer)" \
    VITE_COGNITO_CLIENT_ID="$(tf_output cognito_ui_client_id)" \
    VITE_COGNITO_DOMAIN="$(tf_output cognito_domain_url)" \
    npm --prefix "$root/ui" run build

  step "Uploading the UI"
  aws s3 sync "$root/ui/dist" "s3://$(tf_output ui_bucket)" --delete
  aws cloudfront create-invalidation --distribution-id "$(tf_output ui_distribution_id)" --paths "/*" >/dev/null
}

smoke_test() {
  local ui_url
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
}
