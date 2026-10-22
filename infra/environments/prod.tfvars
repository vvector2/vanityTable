# Non-secret settings for prod, used by scripts/local/deploy.sh and scripts/ci/*.sh (the deploy workflow).
# Image tags are not kept here: the deploy scripts build new ones or read the running ones.
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
