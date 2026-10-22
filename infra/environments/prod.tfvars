# Non-secret settings for prod, used by scripts/deploy.sh and the deploy workflow.
# Image tags are not kept here: deploy.sh builds new ones or reads the running ones.
environment = "prod"
# Terraform refuses to run against any other account.
aws_account_id = "231112632464"
name           = "toaletka"

sync_schedule_enabled = false
olx_query             = "toaletki"

# custom_domain = {
#   name             = "toaletka.example.com"
#   hosted_zone_name = "example.com"
# }
