locals {
  url = local.custom_domain ? "https://${var.custom_domain.name}" : "https://${aws_cloudfront_distribution.ui.domain_name}"
  # Cognito matches callback URLs exactly, including the trailing slash.
  app_urls = concat(["${local.url}/"], var.dev_callback_urls)
}

# Sign-in client for the UI: authorization code flow with PKCE and no client secret,
# since a browser cannot keep one.
resource "aws_cognito_user_pool_client" "ui" {
  name         = "${var.name}-ui"
  user_pool_id = var.cognito_user_pool_id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes = [
    "openid",
    "email",
    "${var.listings_scope_prefix}/read",
    "${var.listings_scope_prefix}/decide",
  ]
  supported_identity_providers  = ["COGNITO"]
  callback_urls                 = local.app_urls
  logout_urls                   = local.app_urls
  explicit_auth_flows           = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
