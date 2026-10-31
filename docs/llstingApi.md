# ListingsApi – design summary

Backend for the Toaletka OLX finder frontend (React). Python + FastAPI, DynamoDB, running on Amazon Lightsail container service (always on, no cold starts).

## Endpoints

| Method | Path                    | Description                          | Request                                                                                                   | Response           |
| ------ | ----------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------- | ------------------ |
| GET    | `/listings`             | Paged list for a tab, newest first   | Query: `searchId` (required), `status` (required: `new`/`saved`/`rejected`), `page` (default 1), `pageSize` (default 20, max 50) | `ListingsPageDto`  |
| PUT    | `/listings/{id}/status` | Set status (Accept, Reject, undo)    | Body: `UpdateListingStatusRequest`                                                                        | `ListingDto`       |
| GET    | `/listings/counts`      | Count per status (tab badges)        | Query: `searchId` (required)                                                                              | `ListingCountsDto` |
| POST   | `/listings`             | Add a new listing (sync job)         | Body: `CreateListingRequest`                                                                              | `201 ListingDto`   |
| DELETE | `/listings/{id}`        | Remove a listing (admin)             | –                                                                                                         | `204`              |
| GET    | `/searches`             | Searches with counts, newest first   | Query: `status` (optional: `active`). Without it: the caller's searches (token `sub`). With it: every user's searches in that status (sync job) | `SearchDto[]` |
| POST   | `/searches`             | Create a search                      | Body: `CreateSearchRequest`                                                                               | `201 SearchDto`    |
| GET    | `/searches/{id}`        | One search (criteria view)           | –                                                                                                         | `SearchDto`        |
| DELETE | `/searches/{id}`        | Delete the search and its listings   | –                                                                                                         | `204`              |
| GET    | `/health`               | Lightsail health check (operational) | –                                                                                                         | `200`              |

Not in MVP: `GET /listings/{id}`, price filter, failure alerting. Not yet: `PUT /searches/{id}` (edit, pause).

Errors: `400` invalid params/body, `404` unknown listing id on PUT or DELETE, unknown search id on `GET`/`DELETE /searches/{id}` or in `POST /listings`, `409` the `searchId` + `sourceId` pair already exists on POST. Body: `{ "error": "VALIDATION_ERROR", "message": "..." }`.

`DELETE /searches/{id}` deletes the listings first, then the search, so a failed call leaves the search in place and can be retried.

## Auth

OAuth 2.0 with the Cognito user pool. Every endpoint except `/health` needs `Authorization: Bearer <access token>`. The API checks the signature (pool JWKS), expiry, issuer (`COGNITO_ISSUER`), `token_use=access` and the endpoint's scope.

| Endpoints                                                       | Scope             | Used by (flow)                         |
| --------------------------------------------------------------- | ----------------- | -------------------------------------- |
| GET `/listings`, `/listings/counts`, `/scan-job/latest`, `/scan-job/{id}` | `listings/read`   | UI (code flow with PKCE)     |
| PUT `/listings/{id}/status`, POST `/scan-job`                   | `listings/decide` | UI (code flow with PKCE)               |
| POST `/listings`, PUT `/scan-job/{id}`                          | `listings/create` | Sync job (client credentials)          |
| DELETE `/listings/{id}`                                         | `listings/admin`  | Admin client (client credentials)      |
| GET `/searches`, `/searches/{id}`                               | `searches/read`   | UI, sync job                           |
| POST `/searches`, DELETE `/searches/{id}`                       | `searches/write`  | UI (code flow with PKCE)               |

No token or an invalid one: `401 UNAUTHORIZED`. Valid token without the scope: `403 FORBIDDEN`. The UI client cannot get `create` or `admin`.

`searches/*` scopes belong to a second resource server, `searches` (`COGNITO_SEARCHES_SCOPE_PREFIX`). The token's `sub` is the search's `userId`.

## DTOs

**ListingDto**: `id` (internal), `searchId` (nullable for listings older than searches), `sourceId` (nullable), `title`, `price` (int, nullable), `currency`, `location` (nullable), `url`, `images[]`, `description` (nullable), `status`, `firstSeenAt`, `updatedAt` (ISO-8601 UTC).

**ListingsPageDto**: `items[]`, `page`, `pageSize`, `totalItems`, `totalPages`.

**CreateListingRequest**: `searchId` (required, must exist), `sourceId` (required: website name plus the listing's ID on that website, e.g. `olx:123`), `title`, `price` (int, nullable), `currency` (default `PLN`), `location` (nullable), `url`, `images[]`, `description` (nullable). The API sets the internal `id`, `status=new`, `searchStatus`, `firstSeenAt` and `updatedAt`. The `id` is a UUIDv5 of `searchId:sourceId`, so the same pair always maps to the same item and a repeated POST returns `409` without changing anything. The same ad in another search is a separate listing with its own status.

**CriteriaDto** (`SeachCriteria.Feature.md`, section 4): `keywords[]` (1 to 10, each 2 to 50 chars), `excludeKeywords[]` (up to 10, each 2 to 50 chars, default `[]`), `priceMin`, `priceMax` (int PLN, nullable, 0 or more, `priceMin <= priceMax`), `location` (nullable: `{ city (1 to 80 chars), radiusKm (int, nullable, 0 or more) }`), `description` (nullable, up to 500 chars). Words are trimmed.

**SearchDto**: `id`, `title`, `criteria` (`CriteriaDto`), `status` (`active`), `counts` (`ListingCountsDto`), `createdAt`, `updatedAt`.

**CreateSearchRequest**: `title` (1 to 80 chars, trimmed), `criteria`. The API sets `id` (UUID), `userId` (token `sub`), `status=active` and the dates.

**UpdateListingStatusRequest**: `{ "status": "new" | "saved" | "rejected" }`.

**ListingCountsDto**: `{ "new": int, "saved": int, "rejected": int }`.

## DynamoDB

Table `Listings`, on-demand billing, partition key `id` (S).

`searchStatus` = `<searchId>#<status>`, written on create and on every status change. A GSI key is one attribute, so the pair is stored explicitly.

GSI `searchStatus-firstSeenAt-index`: partition key `searchStatus` (S), sort key `firstSeenAt` (S), projection ALL. Replaces `status-firstSeenAt-index`.

GSI `sourceId-index`: partition key `sourceId` (S), projection ALL, for lookups by `sourceId`; returns one item per search. A GSI does not enforce uniqueness: the `searchId` + `sourceId` pair is unique because `id` is a UUIDv5 of it and creates use `attribute_not_exists(id)`.

| Access pattern           | Implementation                                                                     |
| ------------------------ | ---------------------------------------------------------------------------------- |
| List a tab, newest first | Query GSI by `searchStatus`, `ScanIndexForward=false`                              |
| Page N                   | Query and skip `(N-1) * pageSize` items (fine at MVP scale)                        |
| Counts                   | Three GSI queries with `Select=COUNT` per search                                   |
| Accept / Reject / undo   | `GetItem` for `searchId`, then `UpdateItem` on `id`, set `status` + `searchStatus` + `updatedAt`, condition on `searchId` |
| Sync insert (POST)       | `PutItem` with `attribute_not_exists(id)` (never overwrites decided listings)      |
| Admin delete             | `DeleteItem` on `id`, condition `attribute_exists(id)`                             |
| Delete a search's listings | Three GSI queries for the ids, then `BatchWriteItem` deletes                     |

Table `Searches`, on-demand billing, partition key `id` (S). Attributes: `userId`, `title`, `criteria` (map, unset fields left out), `status`, `createdAt`, `updatedAt`.

| GSI                      | Keys                       | Access pattern                         |
| ------------------------ | -------------------------- | -------------------------------------- |
| `userId-createdAt-index` | `userId` (S), `createdAt` (S) | Home screen: the user's searches, newest first |
| `status-createdAt-index` | `status` (S), `createdAt` (S) | Sync job: active searches              |

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

Environment variables: `TABLE_NAME`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `COGNITO_ISSUER`, `COGNITO_SCOPE_PREFIX`, `COGNITO_SEARCHES_SCOPE_PREFIX` (default `searches`), `ALLOWED_ORIGINS`, `SCAN_JOBS_TABLE_NAME`, `SCAN_FUNCTION_NAME`, `SEARCHES_TABLE_NAME` (default `Searches`).

Lightsail containers have no task IAM role (not confirmed in docs), so use a dedicated IAM user limited to `dynamodb:Query`, `GetItem`, `UpdateItem`, `PutItem`, `DeleteItem` (plus `BatchWriteItem` on `Listings`) on the `Listings` and `Searches` tables and their GSIs. Pass the keys as sensitive Terraform variables.

Terraform resources: `aws_lightsail_container_service` and `aws_lightsail_container_service_deployment_version`. Verify argument names against the provider docs.
