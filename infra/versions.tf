terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
