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

variable "listing_api_url" {
  description = "Base URL of the Listings API. Empty turns the upload off."
  type        = string
}

variable "listing_api_key" {
  description = "X-API-Key for POST /listings (the API's SYNC_API_KEY)."
  type        = string
  sensitive   = true
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
