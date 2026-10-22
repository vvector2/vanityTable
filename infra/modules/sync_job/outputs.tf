output "repository_url" {
  value = aws_ecr_repository.sync.repository_url
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.sync.id
}

output "cognito_client_secret_parameter" {
  description = "SSM SecureString holding the sync client's secret."
  value       = aws_ssm_parameter.sync_client_secret.name
}

output "function_name" {
  value = one(aws_lambda_function.sync[*].function_name)
}
