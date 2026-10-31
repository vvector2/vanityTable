# Machine client for the sync job: client credentials flow, may create listings and read searches.
resource "aws_cognito_user_pool_client" "sync" {
  name         = "${var.name}-sync"
  user_pool_id = var.cognito_user_pool_id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${var.listings_scope_prefix}/create", "${var.searches_scope_prefix}/read"]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"

  access_token_validity = 60

  token_validity_units {
    access_token = "minutes"
  }
}

# Secrets are read by the Lambda at run time, so they are not visible in its configuration.
resource "aws_ssm_parameter" "sync_client_secret" {
  name  = "/${var.name}/sync/cognito-client-secret"
  type  = "SecureString"
  value = aws_cognito_user_pool_client.sync.client_secret
}
