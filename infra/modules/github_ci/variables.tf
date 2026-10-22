variable "name" {
  type = string
}

variable "environment" {
  description = "GitHub environment whose jobs may assume the deploy role."
  type        = string
}

variable "github_repository" {
  description = "owner/repo allowed to assume the roles."
  type        = string
}

variable "create_oidc_provider" {
  description = "The GitHub OIDC provider exists once per account: one environment creates it, the others look it up."
  type        = bool
}

variable "state_bucket" {
  type = string
}

variable "state_key" {
  type = string
}
