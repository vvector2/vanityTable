# Sync job

OLX browser bot (`src/olx_browser_bot.py`) and the sync Lambda handler (`src/handler.py`) that runs it and sends the listings to the Listings API.
Playwright and Chromium are too big for a zip package, so on AWS the Lambda runs as a container image.

## Run locally (Python)

```
pipenv install --dev
pipenv run playwright install chromium
pipenv run python src/run_local.py --max-pages 1      # through the Lambda handler, saves to output/
pipenv run python src/olx_browser_bot.py --headed     # the bot alone, with a visible browser
```

From the repository root, with the app running (`launch.cmd`), `quickSync` fetches the first OLX page and uploads it to the local API (`quickSync -Pages 3` for more). The local table starts empty, so this is how it gets data.

## Run locally (same container as Lambda)

The image includes the Lambda Runtime Interface Emulator.

```
docker build --platform linux/amd64 --provenance=false -t toaletka-sync .
docker run --rm -p 9000:8080 -e OUTPUT_DIR=/tmp/output -v ${PWD}/output:/tmp/output toaletka-sync
curl -X POST http://localhost:9000/2015-03-31/functions/function/invocations -d '{"max_pages": 1}'
```

## Deploy to AWS

From the repository root, with Docker, Terraform >= 1.10 and the AWS CLI. Full stack setup: `infra/README.md`.

```
./scripts/build-sync-image.ps1 -Push         # needs the ECR repo from the first apply in infra/README.md; prints the image tag
# set sync_image_tag = "<tag>" in infra/terraform.tfvars (api_image_tag must be set there too)
terraform -chdir=infra apply
```

`LISTING_API_URL` is set by Terraform from the `listing_api` module, and stays empty (upload off) until the API has an image. The API key is not in the Lambda configuration: Terraform stores it in SSM and passes the parameter name in `LISTING_API_KEY_PARAMETER`.

Invoke by hand and read the result:

```
aws lambda invoke --function-name toaletka-sync --cli-binary-format raw-in-base64-out --payload '{"max_pages": 1}' out.json
aws s3 cp s3://<sync_output_bucket>/listings/latest.json -
```

The 30-minute schedule exists but is off. Turn it on with `-var sync_schedule_enabled=true`.

## Event and settings

| Event field | Env variable         | Default    |
| ----------- | -------------------- | ---------- |
| `query`     | `OLX_QUERY`          | `toaletki` |
| `max_pages` | `MAX_PAGES`          | all pages  |
| `delay`     | `PAGE_DELAY_SECONDS` | `10`       |

Output goes to S3 when `OUTPUT_BUCKET` is set, otherwise to `OUTPUT_DIR` (default `output/`).

## Upload to the Listings API

After the fetch, every listing is sent to `POST /listings` of the Listings API (`src/listing_upload.py`), one request at a time.

- Idempotent: `sourceId` in the body is the key, the website name plus the listing's ID on that website (`olx:<OLX ID>`). `201` means created, `409` means it already existed. Existing listings are never changed.
- A failed listing is logged and skipped; the rest are still sent and the next run tries it again.
- Transient errors (network, timeout, 429, 5xx) are retried with exponential backoff (`tenacity`). Other errors (400, 401, ...) are not.
- A circuit breaker (`pybreaker`) opens after too many failed listings in a row (400/422 do not count, they are about one listing's data). The upload then stops; it also stops when the Lambda is about to time out.
- Listings from a stopped fetch are sent too. The result has an `upload` summary (`created`, `already_existed`, `failed`, `failed_ids`, ...).

| Env variable                           | Default            |
| -------------------------------------- | ------------------ |
| `LISTING_API_URL`                      | none (upload off)  |
| `LISTING_API_KEY` (the API's `SYNC_API_KEY`) | empty        |
| `LISTING_API_KEY_PARAMETER` (SSM SecureString, used when `LISTING_API_KEY` is empty) | none |
| `LISTING_API_TIMEOUT_SECONDS`          | `10`               |
| `LISTING_API_MAX_ATTEMPTS`             | `3`                |
| `LISTING_API_MAX_CONSECUTIVE_FAILURES` | `10`               |
