# Raw scrape results from the spike. Listings hold no seller data.
resource "aws_s3_bucket" "sync_output" {
  bucket_prefix = "${var.name}-sync-output-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "sync_output" {
  bucket                  = aws_s3_bucket.sync_output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "sync_output" {
  bucket = aws_s3_bucket.sync_output.id

  rule {
    id     = "expire-old-runs"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}
