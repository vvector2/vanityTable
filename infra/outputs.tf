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

# Listings API

output "api_repository_url" {
  value = module.listing_api.repository_url
}

output "api_url" {
  description = "Lightsail public endpoint. The UI reaches it through CloudFront at <ui_url>/api/."
  value       = module.listing_api.url
}

output "api_key" {
  description = "X-API-Key for the UI (VITE_API_KEY). Used until the API checks Cognito tokens."
  value       = module.listing_api.api_key
  sensitive   = true
}

output "admin_api_key" {
  value     = module.listing_api.admin_api_key
  sensitive = true
}

# Sync job

output "sync_repository_url" {
  value = module.sync_job.repository_url
}

output "sync_function_name" {
  value = module.sync_job.function_name
}

output "sync_output_bucket" {
  value = module.sync_job.output_bucket
}

# Common

output "listings_table_name" {
  value = module.common.listings_table_name
}
