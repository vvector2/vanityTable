output "sync_repository_url" {
  value = aws_ecr_repository.sync.repository_url
}

output "sync_function_name" {
  value = aws_lambda_function.sync.function_name
}

output "sync_output_bucket" {
  value = aws_s3_bucket.sync_output.id
}
