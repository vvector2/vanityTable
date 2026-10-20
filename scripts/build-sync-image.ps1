# Builds the sync Lambda image and pushes it to ECR. Prints the tag to pass to Terraform.
# Usage: ./scripts/build-sync-image.ps1 [-Push]
# Needs Docker, and for -Push the AWS CLI plus one `terraform apply` (creates the ECR repository).
param([switch]$Push)

& "$PSScriptRoot/build-image.ps1" -Context syncJob -LocalName toaletka-sync `
    -RepositoryOutput sync_repository_url -TagVariable sync_image_tag -Push:$Push
