"""Sync Lambda: fetches OLX listings, applies criteria, stores results.

Triggered by EventBridge every 30 minutes. See docs/architecture.md, section 5.

Spike stage: runs the browser bot and saves the raw result as JSON, to S3 when
OUTPUT_BUCKET is set (on AWS) or to OUTPUT_DIR (locally, default "output").
Criteria, DynamoDB and expiry come later.

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

from olx_browser_bot import scrape

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


def lambda_handler(event, context):
    query, delay, max_pages = read_settings(event or {})
    logger.info("Sync started: query=%s max_pages=%s delay=%s", query, max_pages, delay)
    result = scrape(query, delay, max_pages, headed=False)
    output = save_result(result)
    logger.info("Saved %d listings to %s (complete=%s)", result["listing_count"], output, result["complete"])
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
    }
