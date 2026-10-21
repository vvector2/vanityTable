"""Sync Lambda: fetches OLX listings, applies criteria, stores results.

Triggered by EventBridge every 30 minutes, or invoked by the Listings API when the UI asks
for a scan (POST /scan-job). See docs/architecture.md, section 5.

Runs the browser bot, saves the raw result as JSON (to S3 when OUTPUT_BUCKET is
set, otherwise to OUTPUT_DIR, default "output"), then sends every fetched listing
to the Listings API when LISTING_API_URL is set (see listing_upload.py).
Criteria and expiry come later.

Event fields (all optional, fall back to environment variables):
- query       OLX search query (OLX_QUERY, default "toaletki")
- max_pages   stop after this many pages (MAX_PAGES, default: all pages)
- delay       seconds between pages (PAGE_DELAY_SECONDS, default 10)
- job_id      scan job to report on (set by POST /scan-job); other runs report under a new id

The run reports `running` and then `succeeded` or `failed` to the Listings API
(PUT /scan-job/{id}), so the UI can show the last successful scan.
"""

import json
import logging
import os
import uuid
from pathlib import Path
from typing import Any

from listing_api_client import ListingApiClient
from listing_upload import upload_listings
from olx_browser_bot import scrape

SOURCE = "olx"

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def read_settings(event: dict[str, Any]) -> tuple[str, float, int | None]:
    def setting(key: str, env_name: str, default: Any = None) -> Any:
        value = event.get(key)
        return value if value is not None else os.environ.get(env_name, default)

    max_pages = setting("max_pages", "MAX_PAGES")
    return (
        setting("query", "OLX_QUERY", "toaletki"),
        float(setting("delay", "PAGE_DELAY_SECONDS", 10)),
        int(max_pages) if max_pages else None,
    )


def save_result(result: dict[str, Any]) -> str:
    """Saves the full scrape result and returns where it went."""
    body = json.dumps(result, ensure_ascii=False, indent=2)
    run_name = result["started_at"].replace(":", "-")
    bucket = os.environ.get("OUTPUT_BUCKET")
    if bucket:
        import boto3

        s3 = boto3.client("s3")
        keys = [f"listings/{run_name}.json", "listings/latest.json"]
        for key in keys:
            s3.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"), ContentType="application/json")
        return f"s3://{bucket}/{keys[0]}"

    out_dir = Path(os.environ.get("OUTPUT_DIR", "output"))
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"listings-{run_name}.json"
    path.write_text(body, encoding="utf-8")
    (out_dir / "listings.json").write_text(body, encoding="utf-8")
    return str(path)


def listing_api_key() -> str:
    """X-API-Key for the Listings API: LISTING_API_KEY, or on AWS the SSM parameter named by LISTING_API_KEY_PARAMETER."""
    key = os.environ.get("LISTING_API_KEY")
    if key:
        return key
    parameter = os.environ.get("LISTING_API_KEY_PARAMETER")
    if not parameter:
        return ""
    import boto3

    response = boto3.client("ssm").get_parameter(Name=parameter, WithDecryption=True)
    return response["Parameter"]["Value"]


def api_client() -> ListingApiClient | None:
    """Client for the Listings API, or None when LISTING_API_URL is not set."""
    base_url = os.environ.get("LISTING_API_URL")
    if not base_url:
        logger.warning("LISTING_API_URL not set, listings and scan status not sent to the Listings API")
        return None
    return ListingApiClient(
        base_url,
        listing_api_key(),
        timeout=float(os.environ.get("LISTING_API_TIMEOUT_SECONDS", 10)),
        max_attempts=int(os.environ.get("LISTING_API_MAX_ATTEMPTS", 3)),
        breaker_fail_max=int(os.environ.get("LISTING_API_MAX_CONSECUTIVE_FAILURES", 10)),
    )


def upload(client: ListingApiClient, listings: list[dict[str, Any]], context: Any) -> dict[str, Any]:
    """Sends listings to the Listings API and returns the upload summary."""
    # Seconds until Lambda kills this run; locally (run_local.py) there is no context and no limit.
    time_left = (lambda: context.get_remaining_time_in_millis() / 1000) if context else None
    summary = upload_listings(client, SOURCE, listings, time_left=time_left)
    return summary.as_dict()


def scan_job_id(event: dict[str, Any], context: Any) -> str:
    """Job id from POST /scan-job; scheduled and hand-started runs get their own."""
    job_id = event.get("job_id")
    if job_id:
        return str(job_id)
    return getattr(context, "aws_request_id", None) or str(uuid.uuid4())


def report_scan_job(client: ListingApiClient | None, job_id: str, status: str, error: str | None = None) -> None:
    """Sends the run's status. A failed report is logged only: it must not stop the sync."""
    if client is None:
        return
    try:
        client.report_scan_job(job_id, status, error)
    except Exception:  # noqa: BLE001
        logger.exception("Reporting scan job %s as %s failed", job_id, status)


def run_error(result: dict[str, Any], upload_summary: dict[str, Any] | None) -> str | None:
    """Why the run did not fully succeed, or None when it did."""
    if not result["complete"]:
        return result["error"] or "Fetch stopped before the last page"
    if upload_summary is None:
        return None
    if upload_summary["stopped_reason"]:
        return f"Upload stopped: {upload_summary['stopped_reason']}"
    if upload_summary["failed"]:
        return f"{upload_summary['failed']} listings could not be uploaded"
    return None


def lambda_handler(event, context):
    event = event or {}
    query, delay, max_pages = read_settings(event)
    job_id = scan_job_id(event, context)
    logger.info("Sync started: job=%s query=%s max_pages=%s delay=%s", job_id, query, max_pages, delay)
    client = api_client()
    report_scan_job(client, job_id, "running")
    try:
        result = scrape(query, delay, max_pages, headed=False)
    except Exception as error:
        report_scan_job(client, job_id, "failed", f"Fetch failed: {error}")
        raise
    # A failed save must not stop the upload: the listings are already in memory.
    try:
        output = save_result(result)
        logger.info("Saved %d listings to %s (complete=%s)", result["listing_count"], output, result["complete"])
    except Exception:  # noqa: BLE001
        logger.exception("Saving the raw result failed")
        output = None
    # Listings from a stopped fetch are still valid, so they are sent too.
    upload_summary = upload(client, result["listings"], context) if client else None
    # Reported last, so a succeeded job means every listing found is already in the API.
    error = run_error(result, upload_summary)
    report_scan_job(client, job_id, "failed" if error else "succeeded", error)
    # A failed fetch is reported, not raised: raising would make async invokes retry,
    # and the fetching rules forbid retries within a run.
    return {
        "status": "ok" if result["complete"] else "stopped",
        "error": result["error"],
        "job_id": job_id,
        "query": query,
        "pages_fetched": result["pages_fetched"],
        "total_pages": result["total_pages"],
        "listing_count": result["listing_count"],
        "output": output,
        "upload": upload_summary,
        "scan_job": "failed" if error else "succeeded",
    }
