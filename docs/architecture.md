# Toaletka: Architecture

Date: 2026-10-17 | Status: draft, based on `toaletka-mvp.md`. Sections marked _(proposal)_ are not yet agreed.

## 1. Decisions so far

| Area                   | Decision                                                                |
| ---------------------- | ----------------------------------------------------------------------- |
| Source                 | OLX public pages, fetched behind an adapter. Unreliability is accepted. |
| Hosting                | AWS, serverless                                                         |
| Backend                | Python (Lambda)                                                         |
| UI                     | Simple React app, mobile-friendly                                       |
| Persistence            | DynamoDB                                                                |
| Infrastructure as code | Terraform                                                               |
| Alerting               | None in MVP. Only the last successful sync time is shown in the UI.     |

## 2. Components

```
EventBridge rule (rate 30 min)
        |
        v
  Sync Lambda ---- reads config ---> SSM Parameter Store
        |
        |--- fetches ---> OLX (via source adapter)
        |
        v
    DynamoDB  <---- API Lambda <---- API Gateway / function URL <---- React UI (S3 + CloudFront)
```

| Component                              | Responsibility                                                                                         |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| EventBridge rule                       | Triggers the sync Lambda with `rate(30 minutes)`                                                       |
| Sync Lambda                            | Fetches listings, applies criteria, stores results, sets expired flags, writes the last-sync timestamp |
| Source adapter (module in sync Lambda) | The only code that knows OLX. Returns normalized listings. Replaceable.                                |
| API Lambda                             | Lists listings by status, records decisions, returns sync status                                       |
| DynamoDB                               | Listings, decisions, sync metadata                                                                     |
| SSM Parameter Store                    | Fuzzy threshold, exceptions list, search settings. Changeable without a redeploy.                      |
| S3 + CloudFront                        | Hosts the static React build                                                                           |

## 3. Normalized listing (adapter contract) _(proposal)_

The adapter returns objects with: `olx_id`, `title`, `description` (may be absent until the listing page is fetched), `price` (number or null), `url`, `photo_urls[]`, `is_active`.

The rest of the app depends only on this shape, not on OLX.

## 4. Data model (DynamoDB) _(proposal)_

One table, pay-per-request.

**Listing item**

- Key: `PK = LISTING#<olx_id>`
- Attributes: `title`, `description`, `price`, `url`, `photo_urls`, `status`, `expired`, `match_score`, `first_seen`, `last_seen`, `decided_at`, `price_at_decision`
- `status` values: `new`, `accepted`, `rejected`, `filtered`

**Sync metadata item**

- Key: `PK = META#sync`
- Attributes: `last_success_at`

**Index**

- One GSI on `status` + `first_seen` to serve the "to review", accepted and rejected views, sorted by newest.

Notes:

- `filtered` holds listings that were seen but did not pass the criteria. Storing them avoids re-fetching their descriptions every run and lets the fuzzy threshold be tuned using their scores.
- `price_at_decision` is stored so a rejected listing's later price change can be compared.
- Photo links are stored, not copies. No seller personal data is stored.

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

## 7. API _(proposal)_

| Endpoint                                       | Purpose                                      |
| ---------------------------------------------- | -------------------------------------------- |
| `GET /listings?status=new\|accepted\|rejected` | List listings, newest first                  |
| `POST /listings/{olx_id}/decision`             | Body: `accepted`, `rejected` or `new` (undo) |
| `GET /sync-status`                             | Returns `last_success_at`                    |

Access protection is an open item (section 10).

## 8. Infrastructure (Terraform)

- One root module with a few files, one environment.
- Remote state in an S3 bucket created by hand before the first apply, with S3 native locking.
- Resources: DynamoDB table and GSI, two Lambdas, Lambda layer for dependencies, EventBridge rule and permission, API Gateway or function URL, SSM parameters, S3 bucket and CloudFront distribution for the UI, IAM roles with least privilege.
- Terraform does not build code. A build script is needed for:
  - Python Lambdas: install dependencies for the Lambda runtime and architecture (`rapidfuzz` has native code, so use pip platform flags or Docker), zip, and publish a layer.
  - React: build, upload to S3, invalidate CloudFront.

## 9. Risks specific to this architecture

- **AWS IP ranges.** Lambda requests come from data-center IPs, which OLX may challenge or block more often than a home connection. The spike must run from Lambda, not a laptop. Fallbacks: a small fetcher at home pushing data to AWS, or a fixed IP via NAT Gateway (costs much more than the rest of the stack and does not hide the data-center origin).
- **JavaScript-rendered pages.** If OLX pages need a headless browser, Lambda packaging gets heavier. The spike will show whether this is needed.
- **Silent failure.** With no alerting, a broken sync is noticed only by a stale timestamp in the UI.

## 10. Open items

- **Spike results** (pending) decide: query scope versus fuzzy search, how to get descriptions, and how listing activity is detected.
- **Access protection:** shared secret header or a single Cognito user.
- **Region:** `eu-central-1` suggested.
- **Python version and dependency packaging approach** (layer versus per-function bundle).
- **First-run behavior:** all existing matches go to review, or sort by newest.

## 11. Next steps

1. Run the spike from Lambda.
2. Confirm the data model and sync flow against the spike results.
3. Set up the Terraform skeleton and remote state.
4. Build the sync Lambda and the adapter, then the API, then the UI.
