data "aws_region" "current" {}

# One user pool for the UI user and the sync job's machine client.
# No self sign-up: users are created by hand (aws cognito-idp admin-create-user).
resource "aws_cognito_user_pool" "main" {
  name                     = var.name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "ACTIVE"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# Cognito domain prefixes are global per region, hence the random suffix.
resource "random_id" "cognito_domain" {
  byte_length = 4
}

# Hosts the sign-in page (UI) and the token endpoint (sync job, client credentials).
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.name}-${random_id.cognito_domain.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# The Listings API as an OAuth resource server. Scopes map to docs/llstingApi.md, section Auth:
# read and decide for the UI, create for the sync job, admin for deleting listings.
resource "aws_cognito_resource_server" "listings" {
  user_pool_id = aws_cognito_user_pool.main.id
  identifier   = "listings"
  name         = "Listings API"

  scope {
    scope_name        = "read"
    scope_description = "List listings and counts"
  }

  scope {
    scope_name        = "decide"
    scope_description = "Accept, reject or undo a listing"
  }

  scope {
    scope_name        = "create"
    scope_description = "Add listings found by the sync job"
  }

  scope {
    scope_name        = "admin"
    scope_description = "Delete listings"
  }
}

# Machine client for admin calls (DELETE /listings/{id}): client credentials, admin scope only.
# Get a token with scripts/local/admin-token.ps1.
resource "aws_cognito_user_pool_client" "admin" {
  name         = "${var.name}-admin"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.listings.identifier}/admin"]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"

  access_token_validity = 60

  token_validity_units {
    access_token = "minutes"
  }
}
