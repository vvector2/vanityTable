# Listings API

FastAPI backend for the Toaletka UI. Design: `docs/llstingApi.md`.

| Method | Path                    | Purpose                              |
| ------ | ----------------------- | ------------------------------------ |
| GET    | `/listings`             | Paged list for a tab, newest first   |
| PUT    | `/listings/{id}/status` | Set status (`new`/`saved`/`rejected`) |
| GET    | `/listings/counts`      | Count per status                     |
| POST   | `/listings`             | Add a new listing (sync job)         |
| DELETE | `/listings/{id}`        | Remove a listing (admin)             |
| GET    | `/health`               | Health check, no token               |

Every other endpoint needs `Authorization: Bearer <Cognito access token>` with the endpoint's scope (`listings/read`, `/decide`, `/create`, `/admin`); see `docs/llstingApi.md`, section Auth. No token or an invalid one gives `401`, a missing scope `403`.

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
| `TABLE_NAME`                                  | no       | `Listings` |
| `ALLOWED_ORIGINS` (comma-separated)           | no       | none       |
| `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | on AWS | –  |
