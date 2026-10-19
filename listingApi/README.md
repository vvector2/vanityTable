# Listings API

FastAPI backend for the Toaletka UI. Design: `docs/llstingApi.md`.

| Method | Path                    | Purpose                              |
| ------ | ----------------------- | ------------------------------------ |
| GET    | `/listings`             | Paged list for a tab, newest first   |
| PUT    | `/listings/{id}/status` | Set status (`new`/`saved`/`rejected`) |
| GET    | `/listings/counts`      | Count per status                     |
| POST   | `/listings`             | Add a new listing (sync job)         |
| DELETE | `/listings/{id}`        | Remove a listing (admin)             |
| GET    | `/health`               | Health check, no API key             |

All `/listings` endpoints need the `X-API-Key` header: `API_KEY` for GET and PUT, `SYNC_API_KEY` for POST, `ADMIN_API_KEY` for DELETE.

## Run locally

```
pipenv install
$env:API_KEY="dev"; $env:TABLE_NAME="Listings"; $env:AWS_REGION="eu-central-1"; $env:ALLOWED_ORIGINS="http://localhost:5173"
pipenv run uvicorn app.main:app --reload --port 8000
```

OpenAPI docs: http://localhost:8000/docs

## Container

```
docker build --platform linux/amd64 -t listings-api .
docker run --rm -p 8000:8000 -e API_KEY=dev -e TABLE_NAME=Listings -e AWS_REGION=eu-central-1 -e AWS_ACCESS_KEY_ID=... -e AWS_SECRET_ACCESS_KEY=... listings-api
```

## Settings

| Env variable                                  | Required | Default    |
| --------------------------------------------- | -------- | ---------- |
| `API_KEY`                                     | yes      | –          |
| `SYNC_API_KEY` (POST disabled if unset)       | no       | –          |
| `ADMIN_API_KEY` (DELETE disabled if unset)    | no       | –          |
| `TABLE_NAME`                                  | no       | `Listings` |
| `ALLOWED_ORIGINS` (comma-separated)           | no       | none       |
| `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | on AWS | –  |
