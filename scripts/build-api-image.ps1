# Builds the Listings API image and pushes it to ECR. Prints the tag to pass to Terraform.
# Usage: ./scripts/build-api-image.ps1 [-Push]
# Needs Docker, and for -Push the AWS CLI plus one `terraform apply` (creates the ECR repository).
param([switch]$Push)

& "$PSScriptRoot/build-image.ps1" -Context listingApi -LocalName toaletka-listings-api `
    -RepositoryOutput api_repository_url -TagVariable api_image_tag -Push:$Push
