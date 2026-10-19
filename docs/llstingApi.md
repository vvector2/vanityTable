# ListingsApi – design summary

Backend for the Toaletka OLX finder frontend (React). Python + FastAPI, DynamoDB, running on Amazon Lightsail container service (always on, no cold starts).

## Endpoints

| Method | Path                    | Description                          | Request                                                                                                   | Response           |
| ------ | ----------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------- | ------------------ |
| GET    | `/listings`             | Paged list for a tab, newest first   | Query: `status` (required: `new`/`saved`/`rejected`), `page` (default 1), `pageSize` (default 20, max 50) | `ListingsPageDto`  |
| PUT    | `/listings/{id}/status` | Set status (Accept, Reject, undo)    | Body: `UpdateListingStatusRequest`                                                                        | `ListingDto`       |
| GET    | `/listings/counts`      | Count per status (tab badges)        | –                                                                                                         | `ListingCountsDto` |
| GET    | `/health`               | Lightsail health check (operational) | –                                                                                                         | `200`              |

Not in MVP: `GET /listings/{id}`, price filter, failure alerting.

Errors: `400` invalid params/body, `404` unknown listing id on PUT. Body: `{ "error": "VALIDATION_ERROR", "message": "..." }`.

Auth (assumption): shared `X-API-Key` header. To be confirmed (single user vs multiple users).

## DTOs

**ListingDto**: `id`, `title`, `price` (int, nullable), `currency`, `location` (nullable), `url`, `images[]`, `description` (nullable), `status`, `firstSeenAt`, `updatedAt` (ISO-8601 UTC).

**ListingsPageDto**: `items[]`, `page`, `pageSize`, `totalItems`, `totalPages`.

**UpdateListingStatusRequest**: `{ "status": "new" | "saved" | "rejected" }`.

**ListingCountsDto**: `{ "new": int, "saved": int, "rejected": int }`.

## DynamoDB

Table `Listings`, on-demand billing, partition key `id` (S).

GSI `status-firstSeenAt-index`: partition key `status` (S), sort key `firstSeenAt` (S), projection ALL.

| Access pattern           | Implementation                                                                     |
| ------------------------ | ---------------------------------------------------------------------------------- |
| List a tab, newest first | Query GSI by `status`, `ScanIndexForward=false`                                    |
| Page N                   | Query and skip `(N-1) * pageSize` items (fine at MVP scale)                        |
| Counts                   | Three GSI queries with `Select=COUNT`                                              |
| Accept / Reject / undo   | `UpdateItem` on `id`, set `status` + `updatedAt`, condition `attribute_exists(id)` |
| Scanner insert           | `PutItem` with `attribute_not_exists(id)` (never overwrites decided listings)      |

Notes:

- GSI reads are eventually consistent. After a PUT the frontend should remove the listing locally instead of trusting an instant re-fetch.
- After Accept/Reject on the New tab with `pageSize=1`, re-fetch the same `page`, then refresh counts.
- Scanning OLX is a separate scheduled Lambda (EventBridge), not part of this API.

## Lightsail

| Setting          | Value                                                                            |
| ---------------- | -------------------------------------------------------------------------------- |
| Service          | `listings-api`, region `eu-central-1`                                            |
| Power / scale    | `nano` (0.25 vCPU, 0.5 GB) / `1`, move to `micro` if memory is tight             |
| Cost             | about $7/month (nano), about $10 (micro)                                         |
| Container / port | `api` / `8000`                                                                   |
| Health check     | `GET /health`, success `200`, interval 10 s, timeout 5 s, healthy 2, unhealthy 3 |
| HTTPS            | Included default endpoint; custom domain optional (needs validated certificate)  |
| Scaling          | Manual only (power and scale, up to 20 nodes); no auto-scaling, no scale to zero |

Environment variables: `TABLE_NAME`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `API_KEY`, `ALLOWED_ORIGINS`.

Lightsail containers have no task IAM role (not confirmed in docs), so use a dedicated IAM user limited to `dynamodb:Query`, `GetItem`, `UpdateItem` on the `Listings` table and its GSI. Pass the keys as sensitive Terraform variables.

Terraform resources: `aws_lightsail_container_service` and `aws_lightsail_container_service_deployment_version`. Verify argument names against the provider docs.
