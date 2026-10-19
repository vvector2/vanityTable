"""Sync Lambda: fetches OLX listings, applies criteria, stores results.

Triggered by EventBridge every 30 minutes. See docs/architecture.md, section 5.

Runs the browser bot, saves the raw result as JSON (to S3 when OUTPUT_BUCKET is
set, otherwise to OUTPUT_DIR, default "output"), then sends every fetched listing
to the Listings API when LISTING_API_URL is set (see listing_upload.py).
Criteria and expiry come later.

Event fields (all optional, fall back to environment variables):
- query       OLX search query (OLX_QUERY, default "toaletki")
- max_pages   stop after this many pages (MAX_PAGES, default: all pages)
- delay       seconds between pages (PAGE_DELAY_SECONDS, default 10)
"""

import json
import logging
import os
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


def upload(listings: list[dict[str, Any]], context: Any) -> dict[str, Any] | None:
    """Sends listings to the Listings API. Returns the upload summary, or None when not configured."""
    base_url = os.environ.get("LISTING_API_URL")
    if not base_url:
        logger.warning("LISTING_API_URL not set, listings not sent to the Listings API")
        return None
    client = ListingApiClient(
        base_url,
        os.environ.get("LISTING_API_KEY", ""),
        timeout=float(os.environ.get("LISTING_API_TIMEOUT_SECONDS", 10)),
        max_attempts=int(os.environ.get("LISTING_API_MAX_ATTEMPTS", 3)),
        breaker_fail_max=int(os.environ.get("LISTING_API_MAX_CONSECUTIVE_FAILURES", 10)),
    )
    # Seconds until Lambda kills this run; locally (run_local.py) there is no context and no limit.
    time_left = (lambda: context.get_remaining_time_in_millis() / 1000) if context else None
    summary = upload_listings(client, SOURCE, listings, time_left=time_left)
    return summary.as_dict()


def lambda_handler(event, context):
    query, delay, max_pages = read_settings(event or {})
    logger.info("Sync started: query=%s max_pages=%s delay=%s", query, max_pages, delay)
    result = scrape(query, delay, max_pages, headed=False)
    # A failed save must not stop the upload: the listings are already in memory.
    try:
        output = save_result(result)
        logger.info("Saved %d listings to %s (complete=%s)", result["listing_count"], output, result["complete"])
    except Exception:  # noqa: BLE001
        logger.exception("Saving the raw result failed")
        output = None
    # Listings from a stopped fetch are still valid, so they are sent too.
    upload_summary = upload(result["listings"], context)
    # A failed fetch is reported, not raised: raising would make async invokes retry,
    # and the fetching rules forbid retries within a run.
    return {
        "status": "ok" if result["complete"] else "stopped",
        "error": result["error"],
        "query": query,
        "pages_fetched": result["pages_fetched"],
        "total_pages": result["total_pages"],
        "listing_count": result["listing_count"],
        "output": output,
        "upload": upload_summary,
    }
