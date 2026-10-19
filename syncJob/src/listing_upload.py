"""Sends fetched listings to the Listings API, one request at a time.

A failed listing is logged and skipped; the rest are still sent. Retries and the
circuit breaker live in listing_api_client. The upload stops early when the
circuit is open or the Lambda is about to time out.

Creates are idempotent, so listings skipped or failed in this run are simply sent
again by the next one.
"""

import logging
from collections.abc import Callable, Iterable
from dataclasses import asdict, dataclass, field
from typing import Any, Protocol

from pybreaker import CircuitBreakerError

from listing_api_client import CreateOutcome, ListingApiError, source_id

logger = logging.getLogger(__name__)


class ListingCreator(Protocol):
    def create_listing(self, source: str, listing: dict[str, Any]) -> CreateOutcome: ...


@dataclass
class UploadSummary:
    total: int = 0
    created: int = 0
    already_existed: int = 0
    failed: int = 0
    skipped: int = 0
    stopped_reason: str | None = None
    failed_ids: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def upload_listings(
    client: ListingCreator,
    source: str,
    listings: Iterable[dict[str, Any]],
    time_left: Callable[[], float] | None = None,
    min_seconds_left: float = 30.0,
) -> UploadSummary:
    listings = list(listings)
    summary = UploadSummary(total=len(listings))

    for index, listing in enumerate(listings):
        remaining = len(listings) - index
        if time_left is not None and time_left() < min_seconds_left:
            summary.stopped_reason = "Lambda time almost up"
            summary.skipped = remaining
            break

        listing_id = str(listing.get("olx_id") or f"<no id, position {index}>")
        key = source_id(source, listing_id)
        try:
            outcome = client.create_listing(source, listing)
        except CircuitBreakerError:
            summary.stopped_reason = "Listings API circuit open"
            summary.skipped = remaining
            break
        except Exception as error:  # noqa: BLE001 - one failed listing must not stop the run
            summary.failed += 1
            summary.failed_ids.append(listing_id)
            # A traceback only helps for unexpected errors; API errors carry their own message.
            logger.error("Listing %s: upload failed: %s", key, error, exc_info=not isinstance(error, ListingApiError))
            continue

        if outcome is CreateOutcome.CREATED:
            summary.created += 1
            logger.info("Listing %s: created", key)
        else:
            summary.already_existed += 1
            logger.debug("Listing %s: already exists", key)

    if summary.stopped_reason:
        logger.error("Upload stopped early: %s, %d listings not sent", summary.stopped_reason, summary.skipped)
    logger.info(
        "Upload finished: %d total, %d created, %d already existed, %d failed, %d skipped",
        summary.total, summary.created, summary.already_existed, summary.failed, summary.skipped,
    )
    return summary
