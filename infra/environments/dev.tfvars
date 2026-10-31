# Non-secret settings for dev, used by scripts/local/deploy.sh and scripts/ci/*.sh (the deploy workflow).
# Image tags are not kept here: the deploy scripts build new ones or read the running ones.
environment = "dev"
# Terraform refuses to run against any other account.
aws_account_id = "090700103422"
name           = "toaletka"

# No 30-minute schedule in dev: start scans from the UI or invoke the Lambda by hand.
sync_schedule_enabled = false
olx_query             = "toaletki"
# Logs are only for debugging here; prod keeps the default 14 days.
sync_log_retention_days = 3

# Sign-in from the local UI (launch.cmd).
dev_callback_urls = ["http://localhost:5173/"]
