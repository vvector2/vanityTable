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

  # The state bucket is created by hand. Pass it at init:
  # terraform init -backend-config="bucket=<state-bucket>"
  backend "s3" {
    key          = "toaletka/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "toaletka"
    }
  }
}

# CloudFront only accepts ACM certificates from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project = "toaletka"
    }
  }
}
