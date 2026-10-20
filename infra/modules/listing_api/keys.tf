# X-API-Key values the API checks today (docs/llstingApi.md, section Auth).
# They stay until the API validates Cognito tokens; then API_KEY and SYNC_API_KEY can go.

resource "random_password" "api_key" {
  length  = 40
  special = false
}

resource "random_password" "sync_api_key" {
  length  = 40
  special = false
}

resource "random_password" "admin_api_key" {
  length  = 40
  special = false
}
