variable "name" {
  type = string
}

variable "custom_domain" {
  description = "UI domain and the Route 53 hosted zone that holds it. Null uses the *.cloudfront.net address."
  type = object({
    name             = string
    hosted_zone_name = string
  })
}

variable "api_origin_domain" {
  description = "Host name of the Listings API, used as the /api/* origin."
  type        = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "listings_scope_prefix" {
  type = string
}

variable "dev_callback_urls" {
  type = list(string)
}
