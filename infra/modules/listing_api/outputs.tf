output "repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "url" {
  description = "Public HTTPS endpoint of the container service, without a trailing slash."
  value       = trimsuffix(aws_lightsail_container_service.api.url, "/")
}

output "origin_domain" {
  description = "Host name CloudFront uses as the API origin."
  value       = trimsuffix(trimprefix(aws_lightsail_container_service.api.url, "https://"), "/")
}
