# Non-secret settings for dev, used by scripts/deploy.sh and the deploy workflow.
# Image tags are not kept here: deploy.sh builds new ones or reads the running ones.
environment = "dev"
# Terraform refuses to run against any other account.
aws_account_id = "090700103422"
name           = "toaletka"

github_repository = "vvector2/vanityTable"
# One GitHub OIDC provider per account.
create_github_oidc_provider = true

sync_schedule_enabled = false
olx_query             = "toaletki"

# dev_callback_urls = ["http://localhost:5173/"]   # only while testing sign-in locally
