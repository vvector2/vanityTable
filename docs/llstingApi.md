# ListingsApi – design summary

Backend for the Toaletka OLX finder frontend (React). Python + FastAPI, DynamoDB, running on Amazon Lightsail container service (always on, no cold starts).

## Endpoints

| Method | Path                    | Description                          | Request                                                                                                   | Response           |
| ------ | ----------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------- | ------------------ |
| GET    | `/listings`             | Paged list for a tab, newest first   | Query: `status` (required: `new`/`saved`/`rejected`), `page` (default 1), `pageSize` (default 20, max 50) | `ListingsPageDto`  |
| PUT    | `/listings/{id}/status` | Set status (Accept, Reject, undo)    | Body: `UpdateListingStatusRequest`                                                                        | `ListingDto`       |
| GET    | `/listings/counts`      | Count per status (tab badges)        | –                                                                                                         | `ListingCountsDto` |
| POST   | `/listings`             | Add a new listing (sync job)         | Body: `CreateListingRequest`                                                                              | `201 ListingDto`   |
| DELETE | `/listings/{id}`        | Remove a listing (admin)             | –                                                                                                         | `204`              |
| GET    | `/health`               | Lightsail health check (operational) | –                                                                                                         | `200`              |

Not in MVP: `GET /listings/{id}`, price filter, failure alerting.

Errors: `400` invalid params/body, `404` unknown listing id on PUT or DELETE, `409` `sourceId` already exists on POST. Body: `{ "error": "VALIDATION_ERROR", "message": "..." }`.

## Auth

OAuth 2.0 with the Cognito user pool. Every endpoint except `/health` needs `Authorization: Bearer <access token>`. The API checks the signature (pool JWKS), expiry, issuer (`COGNITO_ISSUER`), `token_use=access` and the endpoint's scope.

| Endpoints                                                       | Scope             | Used by (flow)                         |
| --------------------------------------------------------------- | ----------------- | -------------------------------------- |
| GET `/listings`, `/listings/counts`, `/scan-job/latest`, `/scan-job/{id}` | `listings/read`   | UI (code flow with PKCE)     |
| PUT `/listings/{id}/status`, POST `/scan-job`                   | `listings/decide` | UI (code flow with PKCE)               |
| POST `/listings`, PUT `/scan-job/{id}`                          | `listings/create` | Sync job (client credentials)          |
| DELETE `/listings/{id}`                                         | `listings/admin`  | Admin client (client credentials)      |

No token or an invalid one: `401 UNAUTHORIZED`. Valid token without the scope: `403 FORBIDDEN`. The UI client cannot get `create` or `admin`.

## DTOs

**ListingDto**: `id` (internal), `sourceId` (nullable), `title`, `price` (int, nullable), `currency`, `location` (nullable), `url`, `images[]`, `description` (nullable), `status`, `firstSeenAt`, `updatedAt` (ISO-8601 UTC).

**ListingsPageDto**: `items[]`, `page`, `pageSize`, `totalItems`, `totalPages`.

**CreateListingRequest**: `sourceId` (required, idempotency key: website name plus the listing's ID on that website, e.g. `olx:123`), `title`, `price` (int, nullable), `currency` (default `PLN`), `location` (nullable), `url`, `images[]`, `description` (nullable). The API sets the internal `id`, `status=new`, `firstSeenAt` and `updatedAt`. The `id` is a UUIDv5 of `sourceId`, so the same `sourceId` always maps to the same item and a repeated POST returns `409` without changing anything.

**UpdateListingStatusRequest**: `{ "status": "new" | "saved" | "rejected" }`.

**ListingCountsDto**: `{ "new": int, "saved": int, "rejected": int }`.

## DynamoDB

Table `Listings`, on-demand billing, partition key `id` (S).

GSI `status-firstSeenAt-index`: partition key `status` (S), sort key `firstSeenAt` (S), projection ALL.

GSI `sourceId-index`: partition key `sourceId` (S), projection ALL, for lookups by `sourceId`. A GSI does not enforce uniqueness: `sourceId` is unique because `id` is a UUIDv5 of it and creates use `attribute_not_exists(id)`.

| Access pattern           | Implementation                                                                     |
| ------------------------ | ---------------------------------------------------------------------------------- |
| List a tab, newest first | Query GSI by `status`, `ScanIndexForward=false`                                    |
| Page N                   | Query and skip `(N-1) * pageSize` items (fine at MVP scale)                        |
| Counts                   | Three GSI queries with `Select=COUNT`                                              |
| Accept / Reject / undo   | `UpdateItem` on `id`, set `status` + `updatedAt`, condition `attribute_exists(id)` |
| Sync insert (POST)       | `PutItem` with `attribute_not_exists(id)` (never overwrites decided listings)      |
| Admin delete             | `DeleteItem` on `id`, condition `attribute_exists(id)`                             |

Notes:

- GSI reads are eventually consistent. After a PUT the frontend should remove the listing locally instead of trusting an instant re-fetch.
- After Accept/Reject on the New tab with `pageSize=1`, re-fetch the same `page`, then refresh counts.
- Scanning OLX is a separate scheduled Lambda (EventBridge), not part of this API. It adds listings through `POST /listings`; a `409` means the listing is already known and is not an error.
- A deleted listing is no longer known, so the next sync adds it again as `new` if it is still on OLX.

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

Environment variables: `TABLE_NAME`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `COGNITO_ISSUER`, `COGNITO_SCOPE_PREFIX`, `ALLOWED_ORIGINS`, `SCAN_JOBS_TABLE_NAME`, `SCAN_FUNCTION_NAME`.

Lightsail containers have no task IAM role (not confirmed in docs), so use a dedicated IAM user limited to `dynamodb:Query`, `GetItem`, `UpdateItem`, `PutItem`, `DeleteItem` on the `Listings` table and its GSI. Pass the keys as sensitive Terraform variables.

Terraform resources: `aws_lightsail_container_service` and `aws_lightsail_container_service_deployment_version`. Verify argument names against the provider docs.
