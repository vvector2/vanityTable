# One root module, one state per environment (environments/); each part of the app is a child module.
# See docs/architecture.md, section 8.

locals {
  # Named here, not read from module.sync_job: sync_job already depends on listing_api,
  # and listing_api needs the name to invoke the Lambda for manual scans.
  sync_function_name = "${var.name}-sync"
}

module "common" {
  source = "./modules/common"

  name = var.name
}

module "listing_api" {
  source = "./modules/listing_api"

  name                  = var.name
  region                = var.region
  power                 = var.api_power
  image_tag             = var.api_image_tag
  listings_table_name   = module.common.listings_table_name
  listings_table_arn    = module.common.listings_table_arn
  scan_jobs_table_name  = module.common.scan_jobs_table_name
  scan_jobs_table_arn   = module.common.scan_jobs_table_arn
  sync_function_name    = local.sync_function_name
  cognito_issuer        = module.common.cognito_issuer
  listings_scope_prefix = module.common.listings_scope_prefix
}

module "frontend" {
  source = "./modules/frontend"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name                  = var.name
  custom_domain         = var.custom_domain
  api_origin_domain     = module.listing_api.origin_domain
  cognito_user_pool_id  = module.common.cognito_user_pool_id
  listings_scope_prefix = module.common.listings_scope_prefix
  dev_callback_urls     = var.dev_callback_urls
}

module "sync_job" {
  source = "./modules/sync_job"

  name             = var.name
  function_name    = local.sync_function_name
  image_tag        = var.sync_image_tag
  schedule_enabled = var.sync_schedule_enabled
  olx_query        = var.olx_query
  max_pages        = var.max_pages
  # Upload stays off until the API has a deployment to receive it.
  listing_api_url       = var.api_image_tag == "" ? "" : module.listing_api.url
  listing_api_key       = module.listing_api.sync_api_key
  cognito_user_pool_id  = module.common.cognito_user_pool_id
  cognito_token_url     = module.common.cognito_token_url
  listings_scope_prefix = module.common.listings_scope_prefix
}
