variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  description = "Prefix for resource names."
  type        = string
  default     = "toaletka"
}

variable "sync_image_tag" {
  description = "Tag of the sync image in ECR, printed by scripts/build-sync-image.ps1."
  type        = string
}

variable "sync_schedule_enabled" {
  description = "Run the sync every 30 minutes. Off during the spike; invoke by hand instead."
  type        = bool
  default     = false
}

variable "olx_query" {
  type    = string
  default = "toaletki"
}

variable "max_pages" {
  description = "Stop after this many result pages. Empty means all pages."
  type        = string
  default     = ""
}

variable "listing_api_url" {
  description = "Base URL of the Listings API the sync sends listings to. Empty turns the upload off."
  type        = string
  default     = ""
}

variable "listing_api_key" {
  description = "X-API-Key for the Listings API."
  type        = string
  default     = ""
  sensitive   = true
}
