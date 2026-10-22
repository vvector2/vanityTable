locals {
  cognito_domain_url = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "listings_table_name" {
  value = aws_dynamodb_table.listings.name
}

output "listings_table_arn" {
  value = aws_dynamodb_table.listings.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_issuer" {
  description = "JWT issuer the API checks tokens against."
  value       = "https://${aws_cognito_user_pool.main.endpoint}"
}

output "cognito_domain_url" {
  value = local.cognito_domain_url
}

output "cognito_token_url" {
  value = "${local.cognito_domain_url}/oauth2/token"
}

output "listings_scope_prefix" {
  description = "Resource server identifier; scopes are <prefix>/read, /decide, /create and /admin."
  value       = aws_cognito_resource_server.listings.identifier
}

output "cognito_admin_client_id" {
  value = aws_cognito_user_pool_client.admin.id
}

output "cognito_admin_client_secret" {
  value     = aws_cognito_user_pool_client.admin.client_secret
  sensitive = true
}

output "scan_jobs_table_name" {
  value = aws_dynamodb_table.scan_jobs.name
}

output "scan_jobs_table_arn" {
  value = aws_dynamodb_table.scan_jobs.arn
}
