"""HTTP client for the Listings API (listingApi/), used by the sync job to add listings.

`POST /listings` (docs/llstingApi.md):
- header `X-API-Key` (the API's `SYNC_API_KEY`), JSON body in camelCase (see `to_request_body`)
- `sourceId` is the idempotency key: the source website name plus the listing's ID on
  that website, e.g. "olx:123". The API generates its own internal `id`.
- `201` the listing was created, `409` it already existed and was left unchanged

Resilience comes from libraries:
- tenacity retries transient failures with exponential backoff (safe, the create is idempotent)
- pybreaker opens the circuit after `breaker_fail_max` failed listings in a row; while it is
  open every call raises `pybreaker.CircuitBreakerError` without a request
"""

import json
import logging
import urllib.error
import urllib.request
from enum import StrEnum
from typing import Any

import pybreaker
from tenacity import Retrying, before_sleep_log, retry_if_exception, stop_after_attempt, wait_exponential

logger = logging.getLogger(__name__)

USER_AGENT = "ToaletkaSync/0.1"
# Worth another attempt: the request may not have reached the API, or the API was briefly unhealthy.
TRANSIENT_STATUSES = {429, 500, 502, 503, 504}
# Rejected because of one listing's data, not because the API is unhealthy: does not trip the breaker.
LISTING_ERROR_STATUSES = {400, 422}
# Longer than a Lambda run, so an open circuit stays open for the rest of the run.
BREAKER_RESET_SECONDS = 15 * 60


class CreateOutcome(StrEnum):
    CREATED = "created"
    ALREADY_EXISTS = "already_exists"


class ListingApiError(Exception):
    """A create request failed. `status` is the HTTP status, or None when no response came back."""

    def __init__(self, message: str, status: int | None = None, transient: bool = False) -> None:
        super().__init__(message)
        self.status = status
        self.transient = transient


def is_transient(error: BaseException) -> bool:
    return isinstance(error, ListingApiError) and error.transient


def is_listing_error(error: BaseException) -> bool:
    return isinstance(error, ListingApiError) and error.status in LISTING_ERROR_STATUSES


def source_id(source: str, website_id: str) -> str:
    """Idempotency key of a listing: website name plus the listing's ID on that website."""
    return f"{source}:{website_id}"


def to_request_body(source: str, listing: dict[str, Any]) -> dict[str, Any]:
    """Maps a normalized listing (adapter contract) to the API request body.

    Only listing data is sent; seller data is never part of a normalized listing.
    """
    price = listing.get("price")
    city, region = listing.get("city"), listing.get("region")
    return {
        "sourceId": source_id(source, listing["olx_id"]),
        "title": listing.get("title") or "",
        "description": listing.get("description"),
        "price": round(price) if price is not None else None,
        "currency": listing.get("currency") or "PLN",
        "location": ", ".join(part for part in (city, region) if part) or None,
        "url": listing.get("url") or "",
        "images": list(listing.get("photo_urls") or []),
    }


class ListingApiClient:
    def __init__(
        self,
        base_url: str,
        api_key: str,
        timeout: float = 10.0,
        max_attempts: int = 3,
        breaker_fail_max: int = 10,
    ) -> None:
        self._url = base_url.rstrip("/") + "/listings"
        self._api_key = api_key
        self._timeout = timeout
        self._retrying = Retrying(
            retry=retry_if_exception(is_transient),
            stop=stop_after_attempt(max(1, max_attempts)),
            wait=wait_exponential(multiplier=1, max=10),
            before_sleep=before_sleep_log(logger, logging.WARNING),
            reraise=True,
        )
        # throw_new_error_on_trip=False: the call that trips the breaker raises its own error,
        # only later calls raise CircuitBreakerError.
        self._breaker = pybreaker.CircuitBreaker(
            fail_max=breaker_fail_max,
            reset_timeout=BREAKER_RESET_SECONDS,
            exclude=[is_listing_error],
            name="listing-api",
            throw_new_error_on_trip=False,
        )

    def create_listing(self, source: str, listing: dict[str, Any]) -> CreateOutcome:
        """Adds one listing.

        Raises ListingApiError when it could not be added, or pybreaker.CircuitBreakerError
        when the circuit is open and no request was made.
        """
        body = to_request_body(source, listing)
        return self._breaker.call(self._retrying, self._post, body)

    def _post(self, body: dict[str, Any]) -> CreateOutcome:
        key = body["sourceId"]
        request = urllib.request.Request(
            self._url,
            data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            method="POST",
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
                "X-API-Key": self._api_key,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                status = response.status
        except urllib.error.HTTPError as error:
            if error.code == 409:
                return CreateOutcome.ALREADY_EXISTS
            raise ListingApiError(
                f"{key}: HTTP {error.code}: {read_error_body(error)}",
                status=error.code,
                transient=error.code in TRANSIENT_STATUSES,
            ) from error
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            reason = getattr(error, "reason", error)
            raise ListingApiError(f"{key}: request failed: {reason}", transient=True) from error

        if status == 201:
            return CreateOutcome.CREATED
        raise ListingApiError(f"{key}: unexpected HTTP {status}", status=status)


def read_error_body(error: urllib.error.HTTPError, limit: int = 500) -> str:
    """Returns the start of the API error body (`{"error", "message"}`) for the log."""
    try:
        return error.read(limit).decode("utf-8", errors="replace") or error.reason
    except Exception:  # noqa: BLE001 - the body is only for the log
        return str(error.reason)
