"""Sync Lambda: fetches OLX listings, applies criteria, stores results.

Triggered by EventBridge every 30 minutes, or invoked by the Listings API when the UI asks
for a scan (POST /scan-job). See docs/architecture.md, section 5.

Runs the browser bot, then sends every fetched listing to the Listings API when
LISTING_API_URL is set (see listing_upload.py).
Criteria and expiry come later.

Event fields (all optional, fall back to environment variables):
- query       OLX search query (OLX_QUERY, default "toaletki")
- max_pages   stop after this many pages (MAX_PAGES, default: all pages)
- delay       seconds between pages, plus 0-0.5 s random (PAGE_DELAY_SECONDS, default 0.5)
- job_id      scan job to report on (set by POST /scan-job); other runs report under a new id
- attempts        loads per page on 403, 5xx, timeout or network error (PAGE_ATTEMPTS, default 3)
- retry_max_wait  longest random wait in seconds before loading a page again
                  (PAGE_RETRY_MAX_WAIT_SECONDS, default 10)

The run reports `running` and then `succeeded` or `failed` to the Listings API
(PUT /scan-job/{id}), so the UI can show the last successful scan.
"""

import logging
import os
import uuid
from dataclasses import dataclass
from typing import Any

from api.cognito_token import TokenProvider
from api.listing_api_client import ListingApiClient
from api.listing_upload import upload_listings
from bots.olx_browser_bot import PAGE_ATTEMPTS, RETRY_MAX_WAIT_SECONDS, scrape

SOURCE = "olx"

logger = logging.getLogger()
logger.setLevel(logging.INFO)


@dataclass(frozen=True)
class Settings:
    query: str
    delay: float
    max_pages: int | None
    attempts: int
    retry_max_wait: float


def read_settings(event: dict[str, Any]) -> Settings:
    def setting(key: str, env_name: str, default: Any = None) -> Any:
        value = event.get(key)
        return value if value is not None else os.environ.get(env_name, default)

    max_pages = setting("max_pages", "MAX_PAGES")
    return Settings(
        query=setting("query", "OLX_QUERY", "toaletki"),
        delay=float(setting("delay", "PAGE_DELAY_SECONDS", 0.5)),
        max_pages=int(max_pages) if max_pages else None,
        attempts=int(setting("attempts", "PAGE_ATTEMPTS", PAGE_ATTEMPTS)),
        retry_max_wait=float(setting("retry_max_wait", "PAGE_RETRY_MAX_WAIT_SECONDS", RETRY_MAX_WAIT_SECONDS)),
    )


def cognito_client_secret() -> str:
    """Sync client's secret: COGNITO_CLIENT_SECRET, or on AWS the SSM parameter named by COGNITO_CLIENT_SECRET_PARAMETER."""
    secret = os.environ.get("COGNITO_CLIENT_SECRET")
    if secret:
        return secret
    parameter = os.environ.get("COGNITO_CLIENT_SECRET_PARAMETER")
    if not parameter:
        raise RuntimeError("COGNITO_CLIENT_SECRET or COGNITO_CLIENT_SECRET_PARAMETER must be set")
    import boto3

    response = boto3.client("ssm").get_parameter(Name=parameter, WithDecryption=True)
    return response["Parameter"]["Value"]


def token_provider() -> TokenProvider:
    """Cognito client credentials for the Listings API (scope listings/create)."""
    return TokenProvider(
        os.environ["COGNITO_TOKEN_URL"],
        os.environ["COGNITO_CLIENT_ID"],
        cognito_client_secret(),
        os.environ.get("COGNITO_SCOPE", "listings/create"),
    )


def api_client() -> ListingApiClient | None:
    """Client for the Listings API, or None when LISTING_API_URL is not set."""
    base_url = os.environ.get("LISTING_API_URL")
    if not base_url:
        logger.warning("LISTING_API_URL not set, listings and scan status not sent to the Listings API")
        return None
    return ListingApiClient(
        base_url,
        token_provider(),
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
    settings = read_settings(event)
    job_id = scan_job_id(event, context)
    logger.info("Sync started: job=%s %s", job_id, settings)
    client = api_client()
    report_scan_job(client, job_id, "running")
    try:
        result = scrape(
            settings.query,
            settings.delay,
            settings.max_pages,
            headed=False,
            attempts=settings.attempts,
            retry_max_wait=settings.retry_max_wait,
        )
    except Exception as error:
        report_scan_job(client, job_id, "failed", f"Fetch failed: {error}")
        raise
    logger.info(
        "Fetched %d listings (complete=%s, pages=%d, retries=%d)",
        result["listing_count"], result["complete"], result["pages_fetched"], result["retries"],
    )
    # Listings from a stopped fetch are still valid, so they are sent too.
    upload_summary = upload(client, result["listings"], context) if client else None
    # Reported last, so a succeeded job means every listing found is already in the API.
    error = run_error(result, upload_summary)
    report_scan_job(client, job_id, "failed" if error else "succeeded", error)
    # A failed fetch is reported, not raised: raising would make async invokes rerun the whole
    # scrape; failed pages are already retried inside the run (olx_browser_bot.load_with_retries).
    return {
        "status": "ok" if result["complete"] else "stopped",
        "error": result["error"],
        "job_id": job_id,
        "query": settings.query,
        "pages_fetched": result["pages_fetched"],
        "retries": result["retries"],
        "total_pages": result["total_pages"],
        "listing_count": result["listing_count"],
        "upload": upload_summary,
        "scan_job": "failed" if error else "succeeded",
    }
