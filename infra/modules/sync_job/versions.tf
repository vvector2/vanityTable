# Sync job (syncJob/): container Lambda that scrapes OLX every 30 minutes and posts
# new listings to the Listings API. See docs/architecture.md, section 5.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
