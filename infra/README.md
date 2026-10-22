# Infrastructure

One Terraform root module, deployed as two environments, `dev` and `prod`. Design: `docs/architecture.md`, section 8.

| Module                | What it holds                                                                                 |
| --------------------- | --------------------------------------------------------------------------------------------- |
| `modules/common`      | DynamoDB `Listings` table, Cognito user pool, its domain and the `listings` resource server   |
| `modules/frontend`    | UI bucket, CloudFront (`/` to S3, `/api/*` to the Listings API), optional ACM + Route 53, Cognito UI client |
| `modules/listing_api` | ECR repository, Lightsail container service and deployment, DynamoDB IAM user, API keys       |
| `modules/sync_job`    | ECR repository, sync Lambda, 30-minute EventBridge rule, Cognito M2M client |

CI access (the GitHub OIDC provider and the `github-actions-<env>` role) is created by hand in each account, outside Terraform; see CI/CD below.

## Scripts

| Folder           | For                         | Holds                                                                                   |
| ---------------- | --------------------------- | --------------------------------------------------------------------------------------- |
| `scripts/local/` | Your machine (interactive)  | `deploy.sh`, `nuke-env.sh`, the PowerShell tools (`launch.ps1`, `quick-sync.ps1`, `admin-token.ps1`, `build-*-image.ps1`, `deploy-ui.ps1`) and `localstack-init/` |
| `scripts/ci/`    | GitHub Actions (never prompt) | `resolve-role.sh`, `plan.sh` and `apply.sh`, one per step of `deploy.yml`              |
| `scripts/lib/`   | Both                        | `deploy-common.sh`: account check, Terraform init, image build and push, plan, apply, UI upload, smoke test |

Change a deploy step in `scripts/lib/deploy-common.sh`, so local and CI deploys stay the same.

## Environments

Each environment is its own AWS account in the organization: `dev` is 090700103422, `prod` is 231112632464.

| File                                   | Holds                                                                  |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `environments/<env>.tfvars`            | Tracked, non-secret settings: `aws_account_id`, `name` prefix, OLX query, schedule, domain |
| `environments/<env>.s3.tfbackend`      | State bucket (one per account, created by hand) and key                |

Both providers set `allowed_account_ids = [var.aws_account_id]`, so Terraform stops when the credentials belong to the other environment's account; the deploy scripts check the same before they build anything. The stack that existed before the split is `dev` (state in `terraform-state-s3-vt-dev`); `prod` starts empty. Both use the `toaletka` prefix, since the accounts keep them apart. There is no `terraform.tfvars`: it would apply to both environments, and the deploy scripts refuse to run while one exists. Image tags are not stored anywhere; the deploy scripts build new ones or, with `--skip-images`, reads the running ones from AWS.

## Deploying from your machine

Needs Terraform >= 1.10, Docker, the AWS CLI and Node, from WSL or Linux. Sign in to the environment's account (for example an IAM Identity Center profile per account):

```
AWS_PROFILE=<dev profile> ./scripts/local/deploy.sh --env dev
AWS_PROFILE=<prod profile> ./scripts/local/deploy.sh --env prod
```

Each account's state bucket is created by hand before its first run, named as in `environments/<env>.s3.tfbackend` (versioning on, public access blocked). `dev` has `terraform-state-s3-vt-dev`; `prod` still needs `terraform-state-s3-vt-prod`.

It initializes `infra/` for that environment, builds and pushes both images, shows the plan, asks before applying, then deploys the UI and calls `/api/health`. The first run of an environment also creates its ECR repositories. The PowerShell scripts in `scripts/local/` (`build-*-image.ps1`, `deploy-ui.ps1`) read Terraform outputs, so they act on whichever environment `infra/` was last initialized for.

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
| `deploy.yml`        | Reusable                    | Plan job → approval → apply job, both as `github-actions-<env>` |

The plan job runs `scripts/ci/plan.sh <env>`: it builds and pushes the images, plans, writes the resource changes to the run summary and uploads `tfplan` (kept 1 day; it holds state values, secrets included). The apply job runs in the GitHub environment, waits for approval and runs `scripts/ci/apply.sh <env>` on the same commit. One deploy per environment at a time; a newer one queues.

On an environment's first run the plan job also creates the ECR repositories without a prompt, so CI can deploy an empty account; no local deployment is needed first.

Each account has its own OIDC provider and one role, `github-actions-<env>`, both created by hand and not managed by Terraform. The workflow builds the role ARN from `aws_account_id` in the environment's tfvars, so a `prod` run can only obtain credentials in the prod account. Both jobs use that role, so the plan job (which runs without approval on every push to `master`) has the same rights as the apply; the gate is the reviewer on the GitHub environment.

### One-time setup

1. Per account: the state bucket (above), an IAM OIDC identity provider for `https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com`, and a role `github-actions-<env>` (`github-actions-dev` exists). Its trust policy allows `sts:AssumeRoleWithWebIdentity` from that provider with `aud` = `sts.amazonaws.com` and `sub` matching both:
   - `repo:vvector2@36629674/vanityTable@1423494022:ref:refs/heads/master` (plan job)
   - `repo:vvector2@36629674/vanityTable@1423494022:environment:<env>` (apply job, runs in the GitHub environment)

   GitHub puts the owner and repository IDs into `sub` (`owner@<id>/repo@<id>`), so a pattern like `repo:vvector2/vanityTable:*` never matches. CloudTrail's failed `AssumeRoleWithWebIdentity` events show the exact `sub` GitHub sent.

   Its permissions must cover the whole stack (for example `AdministratorAccess`) plus the state bucket. No GitHub variables or secrets are needed.
2. Environments (Settings → Environments) `dev` and `prod`: add yourself as a required reviewer, and set deployment branches to `master` only.
3. Branch protection on `master`: require the `CI` checks (`python`, `ui`, `terraform`).

## Removing the environment

```
AWS_PROFILE=<dev profile> ./scripts/local/nuke-env.sh --env dev
```

Destroys everything in the state, including the Listings table (all decisions) and the Cognito user pool. It turns off their deletion protection with the AWS CLI first, and asks you to type the environment name unless you pass `--yes`. Like the deploy scripts, it stops unless you are signed in to that environment's account. The state bucket is kept.

## Notes

- The state holds secrets (the Lightsail IAM user's access key, the Cognito client secrets). Keep the state bucket private.
- The UI calls the API on its own origin at `/api/*`; a CloudFront function strips the `/api` prefix.
- All API calls use Cognito access tokens: the UI signs in (code flow with PKCE), the sync job and the admin client use client credentials. `scripts/local/admin-token.ps1 -Env <env>` prints an admin token for `DELETE /listings/{id}`; it reads the admin client secret from SSM (`cognito_admin_client_secret_parameter`), not from a Terraform output.
- Local sign-in (`launch.cmd`): `dev_callback_urls` in `environments/dev.tfvars` allows `http://localhost:5173/`.
