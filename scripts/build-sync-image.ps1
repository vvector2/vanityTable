# Builds the sync Lambda image and pushes it to ECR. Prints the tag to pass to Terraform.
# Usage: ./scripts/build-sync-image.ps1 [-Push]
# Needs Docker, and for -Push the AWS CLI plus `terraform apply -target=aws_ecr_repository.sync` done once.
param(
    [switch]$Push,
    [string]$Region = "eu-central-1",
    [string]$LocalName = "toaletka-sync"
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$sha = git -C $root rev-parse --short HEAD
$tag = "$sha-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Lambda rejects multi-platform manifests, hence --provenance=false.
docker build --platform linux/amd64 --provenance=false -t "${LocalName}:$tag" -t "${LocalName}:latest" "$root/syncJob"
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

if ($Push) {
    $repo = terraform -chdir="$root/infra" output -raw sync_repository_url
    if ($LASTEXITCODE -ne 0) { throw "Could not read sync_repository_url from Terraform" }
    $registry = $repo.Split("/")[0]
    aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry
    if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }
    docker tag "${LocalName}:$tag" "${repo}:$tag"
    docker push "${repo}:$tag"
    if ($LASTEXITCODE -ne 0) { throw "docker push failed" }
}

Write-Host "Image tag: $tag"
Write-Host "Next: terraform -chdir=infra apply -var sync_image_tag=$tag"
