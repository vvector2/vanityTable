locals {
  # Skipped until the first image is pushed (scripts/build-sync-image.ps1 -Push).
  deploy = var.image_tag != "" ? 1 : 0
}

resource "aws_cloudwatch_log_group" "sync" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "sync" {
  count         = local.deploy
  function_name = var.function_name
  role          = aws_iam_role.sync.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.sync.repository_url}:${var.image_tag}"
  architectures = ["x86_64"]
  # Chromium needs memory; a full run is ~25 pages with a 0.5-1 s pause between them.
  memory_size = 2048
  timeout     = 900

  environment {
    variables = {
      OLX_QUERY = var.olx_query
      # The sync code reads an empty MAX_PAGES as all pages.
      MAX_PAGES = var.max_pages == null ? "" : tostring(var.max_pages)
      # An empty URL turns the upload to the Listings API off.
      LISTING_API_URL           = var.listing_api_url
      LISTING_API_KEY_PARAMETER = aws_ssm_parameter.listing_api_key.name
      # Client credentials for the Listings API; not read by the sync code yet.
      COGNITO_TOKEN_URL               = var.cognito_token_url
      COGNITO_CLIENT_ID               = aws_cognito_user_pool_client.sync.id
      COGNITO_CLIENT_SECRET_PARAMETER = aws_ssm_parameter.sync_client_secret.name
      COGNITO_SCOPE                   = "${var.listings_scope_prefix}/create"
    }
  }

  depends_on = [aws_cloudwatch_log_group.sync, aws_iam_role_policy.sync]
}

# Fetching rules: no retries within a run.
resource "aws_lambda_function_event_invoke_config" "sync" {
  count                  = local.deploy
  function_name          = aws_lambda_function.sync[0].function_name
  maximum_retry_attempts = 0
}
