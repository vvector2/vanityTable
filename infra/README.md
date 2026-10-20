# Infrastructure

One Terraform root module, one environment, one state. Design: `docs/architecture.md`, section 8.

| Module                | What it holds                                                                                 |
| --------------------- | --------------------------------------------------------------------------------------------- |
| `modules/common`      | DynamoDB `Listings` table, Cognito user pool, its domain and the `listings` resource server   |
| `modules/frontend`    | UI bucket, CloudFront (`/` to S3, `/api/*` to the Listings API), optional ACM + Route 53, Cognito UI client |
| `modules/listing_api` | ECR repository, Lightsail container service and deployment, DynamoDB IAM user, API keys       |
| `modules/sync_job`    | ECR repository, sync Lambda, 30-minute EventBridge rule, Cognito M2M client |

## First deployment

Needs Terraform >= 1.10, Docker, the AWS CLI and Node. The state bucket is created by hand once.

```
terraform -chdir=infra init -backend-config="bucket=<state-bucket>"
terraform -chdir=infra apply -var api_image_tag= -var sync_image_tag=   # no images yet: creates ECR, table, Cognito, CloudFront, Lightsail service
./scripts/build-api-image.ps1 -Push                   # prints the API image tag
./scripts/build-sync-image.ps1 -Push                  # prints the sync image tag
terraform -chdir=infra apply -var api_image_tag=<api-tag> -var sync_image_tag=<sync-tag>
./scripts/deploy-ui.ps1
```

The image tags have no default, so an apply without them stops instead of removing the deployments. Keep them in an untracked `infra/terraform.tfvars`:

```
api_image_tag         = "<api-tag>"
sync_image_tag        = "<sync-tag>"
sync_schedule_enabled = true
# custom_domain = {
#   name             = "toaletka.example.com"
#   hosted_zone_name = "example.com"
# }
# dev_callback_urls = ["http://localhost:5173/"]   # only while testing sign-in locally
```

Create the UI user by hand (no self sign-up):

```
aws cognito-idp admin-create-user --user-pool-id <pool-id> --username <email>
```

## Removing the environment

```
./scripts/nuke-env.sh
```

Destroys everything in the state, including the Listings table (all decisions) and the Cognito user pool. It turns off their deletion protection with the AWS CLI first, and asks you to type the environment name unless you pass `--yes`. The state bucket is kept.

## Notes

- The state holds secrets (API keys, the Lightsail IAM user's access key, the Cognito client secret). Keep the state bucket private.
- The UI calls the API on its own origin at `/api/*`; a CloudFront function strips the `/api` prefix.
- The API and the sync job still authenticate with X-API-Key. The Cognito clients and the `COGNITO_*` environment variables are in place for the switch to tokens.
