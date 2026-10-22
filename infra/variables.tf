variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "environment" {
  description = "dev or prod. Values per environment live in environments/<env>.tfvars."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "aws_account_id" {
  description = "Account of this environment in the AWS organization. Terraform stops in any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "name" {
  description = "Prefix for resource names."
  type        = string
}

# Frontend

variable "custom_domain" {
  description = "UI domain and the existing Route 53 hosted zone that holds it, e.g. { name = \"toaletka.example.com\", hosted_zone_name = \"example.com\" }. Null uses the *.cloudfront.net address."
  type = object({
    name             = string
    hosted_zone_name = string
  })
  default = null
}

variable "dev_callback_urls" {
  description = "Extra Cognito sign-in callback URLs for local development, e.g. [\"http://localhost:5173/\"]. Empty: sign-in returns only to the UI URL."
  type        = list(string)
  default     = []
}

# Listings API

# No default: an apply that forgets the tag would remove the running deployment.
variable "api_image_tag" {
  description = "Tag of the Listings API image in ECR, printed by scripts/build-api-image.ps1. Pass \"\" only before the first push; it skips the Lightsail deployment."
  type        = string
  nullable    = false
}

variable "api_power" {
  description = "Lightsail container power: nano or micro."
  type        = string
  default     = "nano"

  validation {
    condition     = contains(["nano", "micro"], var.api_power)
    error_message = "api_power must be nano or micro."
  }
}

# Sync job

# No default, for the same reason as api_image_tag.
variable "sync_image_tag" {
  description = "Tag of the sync image in ECR, printed by scripts/build-sync-image.ps1. Pass \"\" only before the first push; it skips the Lambda."
  type        = string
  nullable    = false
}

variable "sync_schedule_enabled" {
  description = "Run the sync every 30 minutes. Off during the spike; invoke by hand instead."
  type        = bool
  default     = false
}

variable "olx_query" {
  description = "Search phrase sent to OLX."
  type        = string
  default     = "toaletki"
}

variable "max_pages" {
  description = "Stop after this many result pages. Null means all pages."
  type        = number
  default     = null

  validation {
    condition     = var.max_pages == null ? true : var.max_pages >= 1
    error_message = "max_pages must be at least 1, or null for all pages."
  }
}

# CI/CD (GitHub Actions)

variable "github_repository" {
  description = "owner/repo whose workflows may deploy this environment."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "The GitHub OIDC provider exists once per account. False only if the account already has one."
  type        = bool
}

# Set by scripts/deploy.sh from environments/<env>.s3.tfbackend; the CI roles may only touch this state.
variable "state_bucket" {
  type = string
}

variable "state_key" {
  type = string
}
