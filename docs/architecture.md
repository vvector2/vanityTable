# Toaletka: Architecture

Date: 2026-10-22 | Status: draft, based on `mpv.md`; hosting, access, Terraform layout, environments (one AWS account each) and CI/CD decided; CI role created by hand per account. Sections marked _(proposal)_ are not yet agreed.

## 1. Decisions so far

| Area                   | Decision                                                                |
| ---------------------- | ----------------------------------------------------------------------- |
| Source                 | OLX public pages, fetched behind an adapter. Unreliability is accepted. |
| Hosting                | AWS. Sync is serverless (Lambda); the Listings API is an always-on Lightsail container |
| Backend                | Python: sync job on Lambda (container image), Listings API on FastAPI   |
| UI                     | Simple React app, mobile-friendly                                       |
| Persistence            | DynamoDB                                                                |
| Access protection      | Cognito user pool: one UI user (no self sign-up), M2M client for the sync job. X-API-Key stays until the code checks tokens |
| Entry point            | CloudFront serves the UI at `/` and forwards `/api/*` to the Listings API. Route 53 custom domain optional |
| Infrastructure as code | Terraform, one root with modules `common`, `frontend`, `listing_api`, `sync_job` |
| Environments           | `dev` and `prod`, each in its own AWS account of the organization, with its own state bucket |
| CI/CD                  | GitHub Actions with AWS access over OIDC, one hand-made role `github-actions-<env>` per account. Every deploy is plan, approval, apply |
| Alerting               | None in MVP. Only the last successful sync time is shown in the UI.     |

## 2. Components

```
Users --> Route 53 (optional) --> CloudFront --- /      --> S3 (React build)
  |                                   +-------- /api/* --> Lightsail (Listings API, FastAPI) --> DynamoDB
  +--> Cognito (sign-in)                                        ^
                                                                | POST /listings
EventBridge (rate 30 min) --> Sync Lambda ----------------------+
                                  |--- token (client credentials) --> Cognito
                                  +--- fetches ---> OLX (via source adapter)
```

| Component                              | Responsibility                                                                                         |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| EventBridge rule                       | Triggers the sync Lambda with `rate(30 minutes)`                                                       |
| Sync Lambda                            | Fetches listings, applies criteria, sends new listings to the Listings API (`POST /listings`)          |
| Source adapter (module in sync Lambda) | The only code that knows OLX. Returns normalized listings. Replaceable.                                |
| Listings API (Lightsail container)     | FastAPI. Lists listings by status, records decisions, accepts listings from the sync job. See `llstingApi.md` |
| DynamoDB                               | Listings, decisions, sync metadata                                                                     |
| Cognito user pool                      | UI sign-in (code flow with PKCE) and the sync job's client credentials (scope `listings/create`)       |
| SSM Parameter Store                    | Sync job's Cognito client secret; later fuzzy threshold, exceptions list, search settings              |
| S3 + CloudFront (+ Route 53)           | Hosts the static React build; `/api/*` goes to the Listings API on the same origin                     |

## 3. Normalized listing (adapter contract) _(proposal)_

The adapter returns objects with: `olx_id`, `title`, `description` (may be absent until the listing page is fetched), `price` (number or null), `url`, `photo_urls[]`, `is_active`.

The rest of the app depends only on this shape, not on OLX.

## 4. Data model (DynamoDB)

The deployed table follows `llstingApi.md`, section DynamoDB:

- One table, pay-per-request, partition key `id` (UUIDv5 of `sourceId`, e.g. `olx:<olx_id>`).
- Listing attributes: `sourceId`, `title`, `price`, `currency`, `location`, `url`, `images`, `description`, `status`, `firstSeenAt`, `updatedAt`.
- `status` values: `new`, `saved` (accepted), `rejected`.
- GSI `status-firstSeenAt-index` (`status` + `firstSeenAt`) serves the "to review", accepted and rejected views, newest first.
- GSI `sourceId-index` (`sourceId`) for lookups by source ID. Uniqueness of `sourceId` comes from the derived `id`, not from the index.
- Photo links are stored, not copies. No seller personal data is stored.

Still open _(proposal, not in the table yet)_: `match_score`, `expired`, `last_seen`, `price_at_decision`, a `filtered` status for listings seen but not passing the criteria (avoids re-fetching descriptions, helps tune the threshold), and a sync metadata item holding `last_success_at`.

## 5. Sync flow _(proposal)_

1. Read config from SSM (threshold, exceptions).
2. Fetch the candidate list through the adapter.
3. For each listing:
   - Known: update `last_seen`. Never overwrite `status` or the decision.
   - Unknown: fetch the description if needed, compute the fuzzy score, check active and photo criteria. Store as `new` if it passes, otherwise as `filtered`.
4. If the fetch completed fully, mark known listings missing from the results as `expired` (details depend on the spike).
5. Write `last_success_at` last, only if everything above succeeded.

Failure rules:

- Any fetch error, captcha or HTTP 429 stops the run. Nothing is marked expired, no decisions are touched, `last_success_at` is not updated.
- No retries within the run and no circumvention of blocks.
- Fetch rules: one request stream, reasonable User-Agent, no parallelism.

## 6. Matching logic

- Split title and description into words, normalize case and diacritics.
- Compare each word to "toaletka" with a similarity score. The best score is stored as `match_score`.
- Pass if the score is at or above the threshold from SSM and the word is not on the exceptions list.
- Active and at least one photo are exact checks.
- Threshold is tuned empirically during testing. Starting bias: let more through.

## 7. API

The Listings API endpoints are defined in `llstingApi.md`: `GET /listings?status=new|saved|rejected`, `PUT /listings/{id}/status` (accept, reject, undo), `GET /listings/counts`, `POST /listings` (sync job), `DELETE /listings/{id}` (admin) and `GET /health`.

Still open _(proposal)_: an endpoint for `last_success_at` (functional requirement 7).

Access: Cognito scopes `listings/read` and `listings/decide` (UI) and `listings/create` (sync job). Until the API validates tokens, the X-API-Key headers from `llstingApi.md` are used.

## 8. Infrastructure (Terraform)

- One root module (`infra/`), deployed as two environments, `dev` and `prod`, each in its own AWS account of the organization. Each has its own state bucket in its account and its settings, account ID included, in `infra/environments/<env>.tfvars`. The providers allow only that account (`allowed_account_ids`), so one environment cannot be applied to the other's account. The stack that predates the split is `dev`. Each part of the app is a child module:

| Module        | Resources                                                                                          |
| ------------- | -------------------------------------------------------------------------------------------------- |
| `common`      | DynamoDB `Listings` table and GSI, Cognito user pool, domain and `listings` resource server        |
| `frontend`    | S3 bucket, CloudFront (OAC, `/api/*` behavior, prefix-stripping function), optional ACM + Route 53, Cognito UI client |
| `listing_api` | ECR repository, Lightsail container service and deployment, IAM user for DynamoDB, API keys        |
| `sync_job`    | ECR repository, Lambda (container image), EventBridge rule, Cognito M2M client, SSM secret |

- Remote state in an S3 bucket per account, created by hand before the environment's first apply, with S3 native locking (`terraform-state-s3-vt-dev`, `terraform-state-s3-vt-prod`).
- CI access is outside Terraform: in each account the GitHub OIDC provider and the role `github-actions-<env>` are created by hand.
- Terraform does not build code. Scripts in `scripts/` do:
  - `build-sync-image.ps1` and `build-api-image.ps1`: build and push the container images; the tag goes to Terraform.
  - `deploy-ui.ps1`: build React, upload to S3, invalidate CloudFront.
  - `deploy.sh --env <env>`: all of the above plus plan and apply, for one environment.
- CI/CD (`.github/workflows/`, setup in `infra/README.md`):
  - Pull requests: Python lint, UI build, `terraform fmt` and `validate`. No AWS access.
  - A push to `master` deploys `dev`. A manual workflow deploys any ref to `dev` or `prod`.
  - Each deploy assumes `github-actions-<env>` in the environment's own account (ARN built from its tfvars). The plan job builds and pushes the images (creating the ECR repositories on the first run) and plans. The apply job waits for approval on the GitHub environment, then applies that plan with the same role and uploads the UI.
  - The role trusts this repository's `master` branch (plan job) and its GitHub environment (apply job). Since the role exists before Terraform runs, CI can deploy an empty account.

## 9. Risks specific to this architecture

- **Lightsail is always on.** About $7/month (nano) per environment, so about $14/month for `dev` and `prod`, the largest fixed cost. Accepted for no cold starts.
- **One broad CI role.** Plan and apply use the same role, so the plan job, which runs without approval on every push to `master`, has full deploy rights. The real gate is the required reviewer on the GitHub environment and branch protection on `master`. The role is hand-made, so it is not reviewed in code. The plan artifact holds state values, secrets included, and is kept for one day.
- **AWS IP ranges.** Lambda requests come from data-center IPs, which OLX may challenge or block more often than a home connection. The spike must run from Lambda, not a laptop. Fallbacks: a small fetcher at home pushing data to AWS, or a fixed IP via NAT Gateway (costs much more than the rest of the stack and does not hide the data-center origin).
- **JavaScript-rendered pages.** If OLX pages need a headless browser, Lambda packaging gets heavier. The spike will show whether this is needed.
- **Silent failure.** With no alerting, a broken sync is noticed only by a stale timestamp in the UI.

## 10. Open items

- **Spike results** (pending) decide: query scope versus fuzzy search, how to get descriptions, and how listing activity is detected.
- **API token checks:** the Listings API and the sync job still use X-API-Key; switching them to Cognito tokens is pending code work.
- **First-run behavior:** all existing matches go to review, or sort by newest.

## 11. Next steps

1. Run the spike from Lambda.
2. Confirm the data model and sync flow against the spike results.
3. `dev` has its state bucket, OIDC provider and `github-actions-dev` role; set up the GitHub environments and deploy it through CI. For `prod`, create the same by hand (`terraform-state-s3-vt-prod`, `github-actions-prod`), see `infra/README.md`.
4. Validate Cognito tokens in the Listings API and use client credentials in the sync job; then drop `API_KEY` and `SYNC_API_KEY`.
