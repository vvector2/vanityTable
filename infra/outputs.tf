# Frontend

output "ui_url" {
  value = module.frontend.url
}

output "ui_bucket" {
  value = module.frontend.bucket
}

output "ui_distribution_id" {
  value = module.frontend.distribution_id
}

output "cognito_ui_client_id" {
  value = module.frontend.cognito_client_id
}

output "cognito_domain_url" {
  value = module.common.cognito_domain_url
}

output "cognito_issuer" {
  description = "Token issuer: the UI's OIDC authority and the API's COGNITO_ISSUER."
  value       = module.common.cognito_issuer
}

output "cognito_token_url" {
  value = module.common.cognito_token_url
}

output "listings_scope_prefix" {
  value = module.common.listings_scope_prefix
}

output "cognito_admin_client_id" {
  value = module.common.cognito_admin_client_id
}

output "cognito_admin_client_secret_parameter" {
  value = module.common.cognito_admin_client_secret_parameter
}

# Listings API

output "api_repository_url" {
  value = module.listing_api.repository_url
}

output "api_url" {
  description = "Lightsail public endpoint. The UI reaches it through CloudFront at <ui_url>/api/."
  value       = module.listing_api.url
}


# Sync job

output "sync_repository_url" {
  value = module.sync_job.repository_url
}

output "sync_function_name" {
  value = module.sync_job.function_name
}

output "sync_cognito_client_id" {
  value = module.sync_job.cognito_client_id
}

output "sync_cognito_client_secret_parameter" {
  value = module.sync_job.cognito_client_secret_parameter
}

# Common

output "listings_table_name" {
  value = module.common.listings_table_name
}
