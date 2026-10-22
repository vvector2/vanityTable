output "repository_url" {
  value = aws_ecr_repository.sync.repository_url
}

output "function_name" {
  value = one(aws_lambda_function.sync[*].function_name)
}
