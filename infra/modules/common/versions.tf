# Shared resources used by more than one part of the app: the Listings table and Cognito.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
