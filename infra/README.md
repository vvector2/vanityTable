# Infrastructure

One Terraform root module, deployed as two environments, `dev` and `prod`. Design: `docs/architecture.md`, section 8.

| Module                | What it holds                                                                                 |
| --------------------- | --------------------------------------------------------------------------------------------- |
| `modules/common`      | DynamoDB `Listings` table, Cognito user pool, its domain and the `listings` resource server   |
| `modules/frontend`    | UI bucket, CloudFront (`/` to S3, `/api/*` to the Listings API), optional ACM + Route 53, Cognito UI client |
| `modules/listing_api` | ECR repository, Lightsail container service and deployment, DynamoDB IAM user, API keys       |
| `modules/sync_job`    | ECR repository, sync Lambda, 30-minute EventBridge rule, Cognito M2M client |
| `modules/github_ci`   | GitHub OIDC provider, `<name>-github-plan` (read-only, pushes images) and `<name>-github-deploy` roles |

## Environments

Each environment is its own AWS account in the organization: `dev` is 090700103422, `prod` is 231112632464.

| File                                   | Holds                                                                  |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `environments/<env>.tfvars`            | Tracked, non-secret settings: `aws_account_id`, `name` prefix, OLX query, schedule, domain |
| `environments/<env>.s3.tfbackend`      | State bucket (one per account, created by hand) and key                |

Both providers set `allowed_account_ids = [var.aws_account_id]`, so Terraform stops when the credentials belong to the other environment's account; `deploy.sh` checks the same before it builds anything. The stack that existed before the split is `dev` (state in `terraform-state-s3-vt-dev`); `prod` starts empty. Both use the `toaletka` prefix, since the accounts keep them apart. There is no `terraform.tfvars`: it would apply to both environments, and `scripts/deploy.sh` refuses to run while one exists. Image tags are not stored anywhere; `deploy.sh` builds new ones or, with `--skip-images`, reads the running ones from AWS.

## Deploying from your machine

Needs Terraform >= 1.10, Docker, the AWS CLI and Node, from WSL or Linux. Sign in to the environment's account (for example an IAM Identity Center profile per account):

```
AWS_PROFILE=<dev profile> ./scripts/deploy.sh --env dev
AWS_PROFILE=<prod profile> ./scripts/deploy.sh --env prod
```

Before the first `prod` run, create its state bucket in the prod account, named as in `environments/prod.s3.tfbackend` (versioning on, public access blocked).

It initializes `infra/` for that environment, builds and pushes both images, shows the plan, asks before applying, then deploys the UI and calls `/api/health`. The first run of an environment also creates its ECR repositories and CI roles. The PowerShell scripts (`build-*-image.ps1`, `deploy-ui.ps1`) read Terraform outputs, so they act on whichever environment `infra/` was last initialized for.

Create the UI user by hand (no self sign-up), once per environment:

```
aws cognito-idp admin-create-user --user-pool-id <pool-id> --username <email>
```

## CI/CD (GitHub Actions)

| Workflow            | Trigger                     | Does                                                         |
| ------------------- | --------------------------- | ------------------------------------------------------------ |
| `ci.yml`            | Pull request to `master`    | ruff, UI build (with typecheck), `terraform fmt` and `validate`. No AWS access |
| `deploy-dev.yml`    | Push to `master`            | Calls `deploy.yml` for `dev`                                 |
| `deploy-manual.yml` | "Run workflow" from `master` | Calls `deploy.yml` for `dev` or `prod`, with an optional ref  |
| `deploy.yml`        | Reusable                    | Plan job (plan role) → approval → apply job (deploy role)    |

The plan job runs `deploy.sh --plan-only`: it builds and pushes the images, plans, writes the resource changes to the run summary and uploads `tfplan` (kept 1 day; it holds state values, secrets included). The apply job runs in the GitHub environment, waits for approval and runs `deploy.sh --apply-plan` on the same commit. One deploy per environment at a time; a newer one queues.

Each account has its own OIDC provider and roles. The workflow builds the role ARNs from `aws_account_id` and `name` in the environment's tfvars, so a `prod` run can only obtain credentials in the prod account. The roles trust only this repository: the plan role trusts workflows running on `master`, and the deploy role trusts jobs in its GitHub environment. The deploy role manages `github_ci` too, so it could widen its own policy; the gate is the reviewer.

### One-time setup

1. Deploy both environments once locally (above). This creates the roles. No GitHub variables or secrets are needed.
2. Environments (Settings → Environments) `dev` and `prod`: add yourself as a required reviewer, and set deployment branches to `master` only.
3. Branch protection on `master`: require the `CI` checks (`python`, `ui`, `terraform`).

## Removing the environment

```
AWS_PROFILE=<dev profile> ./scripts/nuke-env.sh --env dev
```

Destroys everything in the state, including the Listings table (all decisions) and the Cognito user pool. It turns off their deletion protection with the AWS CLI first, and asks you to type the environment name unless you pass `--yes`. Like `deploy.sh`, it stops unless you are signed in to that environment's account. The state bucket is kept.

## Notes

- The state holds secrets (API keys, the Lightsail IAM user's access key, the Cognito client secret). Keep the state bucket private.
- The UI calls the API on its own origin at `/api/*`; a CloudFront function strips the `/api` prefix.
- The API and the sync job still authenticate with X-API-Key. The Cognito clients and the `COGNITO_*` environment variables are in place for the switch to tokens.
- Local sign-in testing: `dev_callback_urls` in `environments/dev.tfvars`.
