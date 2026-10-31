# Listings API

FastAPI backend for the Toaletka UI. Design: `docs/llstingApi.md`.

| Method | Path                    | Purpose                              |
| ------ | ----------------------- | ------------------------------------ |
| GET    | `/listings`             | Paged list for a tab, newest first   |
| PUT    | `/listings/{id}/status` | Set status (`new`/`saved`/`rejected`) |
| GET    | `/listings/counts`      | Count per status                     |
| POST   | `/listings`             | Add a new listing (sync job)         |
| DELETE | `/listings/{id}`        | Remove a listing (admin)             |
| GET    | `/searches`             | Searches with counts per status      |
| POST   | `/searches`             | Create a search                      |
| GET    | `/searches/{id}`        | One search                           |
| DELETE | `/searches/{id}`        | Delete a search and its listings     |
| GET    | `/health`               | Health check, no token               |

Every other endpoint needs `Authorization: Bearer <Cognito access token>` with the endpoint's scope (`listings/read`, `/decide`, `/create`, `/admin`, `searches/read`, `/write`); see `docs/llstingApi.md`, section Auth. No token or an invalid one gives `401`, a missing scope `403`.

## Code layout

`app/main.py` builds the app; a request goes endpoint -> handler -> repository.

| Folder           | Holds                                                                  |
| ---------------- | ---------------------------------------------------------------------- |
| `app/endpoint/`  | FastAPI routers, one file per resource, plus the scope checks          |
| `app/handlers/`  | Use cases called by the routers; raise `ApiError` (404, 409, 502)      |
| `app/core/`      | Domain classes (plain dataclasses and enums): `Listing`, `Search`, `Criteria`, `ScanJob`, ... |
| `app/dto/`       | Request and response bodies only (camelCase JSON, validation)          |
| `app/infra/`     | DynamoDB repositories, the sync Lambda trigger, settings               |
| `app/api_layer/` | Token checks, error type and handlers, dependency wiring               |

Handlers and repositories work only with `core` classes. Endpoints convert at the edge: a request DTO's `to_core()` goes in, a response DTO's `from_core()` comes out. DTOs may repeat core fields; that is on purpose. `core` imports nothing from the other folders.

## Run locally

`launch.cmd` in the repo root does this with the dev Cognito pool. By hand:

```
pipenv install
$env:COGNITO_ISSUER="https://cognito-idp.eu-central-1.amazonaws.com/<pool id>"; $env:TABLE_NAME="Listings"; $env:AWS_REGION="eu-central-1"; $env:ALLOWED_ORIGINS="http://localhost:5173"
pipenv run uvicorn app.main:app --reload --port 8000
```

OpenAPI docs: http://localhost:8000/docs

## Container

```
docker build --platform linux/amd64 -t listings-api .
docker run --rm -p 8000:8000 -e COGNITO_ISSUER=... -e TABLE_NAME=Listings -e AWS_REGION=eu-central-1 -e AWS_ACCESS_KEY_ID=... -e AWS_SECRET_ACCESS_KEY=... listings-api
```

## Settings

| Env variable                                  | Required | Default    |
| --------------------------------------------- | -------- | ---------- |
| `COGNITO_ISSUER` (user pool issuer URL)       | yes      | –          |
| `COGNITO_SCOPE_PREFIX`                        | no       | `listings` |
| `COGNITO_SEARCHES_SCOPE_PREFIX`               | no       | `searches` |
| `TABLE_NAME`                                  | no       | `Listings` |
| `SEARCHES_TABLE_NAME`                         | no       | `Searches` |
| `ALLOWED_ORIGINS` (comma-separated)           | no       | none       |
| `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | on AWS | –  |
