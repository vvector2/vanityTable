# React UI (ui/): S3 + CloudFront, optional Route 53 domain, Cognito sign-in client.
# CloudFront serves the build at / and forwards /api/* to the Listings API.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
