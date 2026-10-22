# Shared by build-api-image.ps1 and build-sync-image.ps1: builds a container image and,
# with -Push, pushes it to the ECR repository named by a Terraform output. Prints the tag.
param(
    [Parameter(Mandatory)][string]$Context,
    [Parameter(Mandatory)][string]$LocalName,
    [Parameter(Mandatory)][string]$RepositoryOutput,
    [Parameter(Mandatory)][string]$TagVariable,
    [switch]$Push
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$sha = git -C $root rev-parse --short HEAD
$tag = "$sha-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Lambda and Lightsail run x86_64; Lambda also rejects multi-platform manifests, hence --provenance=false.
docker build --platform linux/amd64 --provenance=false -t "${LocalName}:$tag" -t "${LocalName}:latest" "$root/$Context"
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

if ($Push) {
    $repo = terraform -chdir="$root/infra" output -raw $RepositoryOutput
    if ($LASTEXITCODE -ne 0) { throw "Could not read $RepositoryOutput from Terraform" }
    # <account>.dkr.ecr.<region>.amazonaws.com/<name>: the region follows the Terraform stack.
    $registry = $repo.Split("/")[0]
    $region = $registry.Split(".")[3]
    aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
    if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }
    docker tag "${LocalName}:$tag" "${repo}:$tag"
    if ($LASTEXITCODE -ne 0) { throw "docker tag failed" }
    docker push "${repo}:$tag"
    if ($LASTEXITCODE -ne 0) { throw "docker push failed" }
}

Write-Host "Image tag: $tag"
Write-Host "Next: terraform -chdir=infra apply -var-file=environments/<env>.tfvars -var $TagVariable=$tag (plus the other image's tag)"
