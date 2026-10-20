output "url" {
  value = local.url
}

output "bucket" {
  value = aws_s3_bucket.ui.id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.ui.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.ui.id
}
