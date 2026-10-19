resource "aws_cloudwatch_log_group" "sync" {
  name              = "/aws/lambda/${var.name}-sync"
  retention_in_days = 14
}

resource "aws_lambda_function" "sync" {
  function_name = "${var.name}-sync"
  role          = aws_iam_role.sync.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.sync.repository_url}:${var.sync_image_tag}"
  architectures = ["x86_64"]
  # Chromium needs memory; a full run is ~25 pages with a 10 s pause between them.
  memory_size = 2048
  timeout     = 900

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.sync_output.id
      OLX_QUERY     = var.olx_query
      MAX_PAGES     = var.max_pages
      # An empty URL turns the upload to the Listings API off.
      LISTING_API_URL = var.listing_api_url
      LISTING_API_KEY = var.listing_api_key
    }
  }

  depends_on = [aws_cloudwatch_log_group.sync, aws_iam_role_policy.sync]
}

# Fetching rules: no retries within a run.
resource "aws_lambda_function_event_invoke_config" "sync" {
  function_name          = aws_lambda_function.sync.function_name
  maximum_retry_attempts = 0
}
