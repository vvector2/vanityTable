terraform {
  required_version = ">= 1.10"

  required_providers {
    # Tested with 6.69; it uses key_schema blocks on DynamoDB global secondary indexes.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Each environment's account has its own state bucket, created by hand. Pass it at init:
  # terraform init -reconfigure -backend-config=environments/<env>.s3.tfbackend
  backend "s3" {
    region       = "eu-central-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  # dev and prod live in separate accounts: never apply one environment to the other's account.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = "toaletka"
      Environment = var.environment
    }
  }
}

# CloudFront only accepts ACM certificates from us-east-1.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = "toaletka"
      Environment = var.environment
    }
  }
}
