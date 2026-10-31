variable "name" {
  type = string
}

variable "function_name" {
  description = "Lambda name; the Listings API invokes it by this name for manual scans."
  type        = string
}

variable "image_tag" {
  description = "Tag of the sync image in ECR. Empty skips the Lambda."
  type        = string
}

variable "schedule_enabled" {
  type = bool
}

variable "olx_query" {
  type = string
}

variable "max_pages" {
  description = "Stop after this many result pages. Null means all pages."
  type        = number
}

variable "page_delay_seconds" {
  description = "Seconds between OLX results pages, plus a random 0 to 5 s."
  type        = number
}

variable "log_retention_days" {
  description = "Days the Lambda's CloudWatch logs are kept."
  type        = number
}

variable "listing_api_url" {
  description = "Base URL of the Listings API. Empty turns the upload off."
  type        = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_token_url" {
  type = string
}

variable "listings_scope_prefix" {
  type = string
}
