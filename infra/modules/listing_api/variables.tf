variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "power" {
  description = "Lightsail container power: nano or micro."
  type        = string
}

variable "image_tag" {
  description = "Tag of the API image in ECR. Empty skips the deployment."
  type        = string
}

variable "listings_table_name" {
  type = string
}

variable "listings_table_arn" {
  type = string
}

variable "scan_jobs_table_name" {
  type = string
}

variable "scan_jobs_table_arn" {
  type = string
}

variable "sync_function_name" {
  description = "Sync Lambda that POST /scan-job invokes."
  type        = string
}

variable "cognito_issuer" {
  type = string
}

variable "listings_scope_prefix" {
  type = string
}
