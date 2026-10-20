resource "aws_lightsail_container_service" "api" {
  name  = "${var.name}-listings-api"
  power = var.power
  scale = 1

  private_registry_access {
    ecr_image_puller_role {
      is_active = true
    }
  }
}

# Skipped until the first image is pushed (scripts/build-api-image.ps1 -Push).
resource "aws_lightsail_container_service_deployment_version" "api" {
  count        = var.image_tag == "" ? 0 : 1
  service_name = aws_lightsail_container_service.api.name

  container {
    container_name = "api"
    image          = "${aws_ecr_repository.api.repository_url}:${var.image_tag}"

    environment = {
      TABLE_NAME            = var.listings_table_name
      AWS_REGION            = var.region
      AWS_ACCESS_KEY_ID     = aws_iam_access_key.api.id
      AWS_SECRET_ACCESS_KEY = aws_iam_access_key.api.secret
      API_KEY               = random_password.api_key.result
      SYNC_API_KEY          = random_password.sync_api_key.result
      ADMIN_API_KEY         = random_password.admin_api_key.result
      # The UI calls the API through CloudFront on its own origin, so CORS stays off.
      ALLOWED_ORIGINS = ""
      # For Cognito token checks; not read by the API yet.
      COGNITO_ISSUER       = var.cognito_issuer
      COGNITO_SCOPE_PREFIX = var.listings_scope_prefix
    }

    ports = {
      "8000" = "HTTP"
    }
  }

  public_endpoint {
    container_name = "api"
    container_port = 8000

    health_check {
      path                = "/health"
      success_codes       = "200"
      interval_seconds    = 10
      timeout_seconds     = 5
      healthy_threshold   = 2
      unhealthy_threshold = 3
    }
  }

  # The pull permission must be in place before Lightsail fetches the image.
  depends_on = [aws_ecr_repository_policy.api]
}
