# Sync job

OLX browser bot (`src/olx_browser_bot.py`) and the sync Lambda handler (`src/handler.py`) that runs it.
Playwright and Chromium are too big for a zip package, so on AWS the Lambda runs as a container image.

## Run locally (Python)

```
pipenv install --dev
pipenv run playwright install chromium
pipenv run python src/run_local.py --max-pages 1      # through the Lambda handler, saves to output/
pipenv run python src/olx_browser_bot.py --headed     # the bot alone, with a visible browser
```

## Run locally (same container as Lambda)

The image includes the Lambda Runtime Interface Emulator.

```
docker build --platform linux/amd64 --provenance=false -t toaletka-sync .
docker run --rm -p 9000:8080 -e OUTPUT_DIR=/tmp/output -v ${PWD}/output:/tmp/output toaletka-sync
curl -X POST http://localhost:9000/2015-03-31/functions/function/invocations -d '{"max_pages": 1}'
```

## Deploy to AWS

From the repository root, with Docker, Terraform >= 1.10 and the AWS CLI. The state bucket is created by hand once.

```
terraform -chdir=infra init -backend-config="bucket=<state-bucket>"
terraform -chdir=infra apply -target="aws_ecr_repository.sync" -var sync_image_tag=none   # first time only: the repo must exist before a push
./scripts/build-sync-image.ps1 -Push                              # prints the image tag
terraform -chdir=infra apply -var sync_image_tag=<tag>
```

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
