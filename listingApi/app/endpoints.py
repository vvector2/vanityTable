"""API endpoints. See docs/llstingApi.md, section Endpoints."""

import math
from typing import Annotated

from fastapi import APIRouter, Depends, Query

from app.api_utils import ApiError, Repository, require_api_key
from app.models import (
    ListingCountsDto,
    ListingDto,
    ListingsPageDto,
    ListingStatus,
    UpdateListingStatusRequest,
)
from app.repository import ListingNotFound

health_router = APIRouter()
listings_router = APIRouter(prefix="/listings", dependencies=[Depends(require_api_key)])


@health_router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@listings_router.get("", response_model=ListingsPageDto)
def list_listings(
    repository: Repository,
    status: ListingStatus,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(alias="pageSize", ge=1, le=50)] = 20,
) -> ListingsPageDto:
    total_items = repository.count(status)
    return ListingsPageDto(
        items=repository.list_page(status, page, page_size),
        page=page,
        page_size=page_size,
        total_items=total_items,
        total_pages=math.ceil(total_items / page_size),
    )


@listings_router.get("/counts", response_model=ListingCountsDto)
def listing_counts(repository: Repository) -> ListingCountsDto:
    return ListingCountsDto(**{status.value: repository.count(status) for status in ListingStatus})


@listings_router.put("/{listing_id}/status", response_model=ListingDto)
def update_listing_status(
    listing_id: str, body: UpdateListingStatusRequest, repository: Repository
) -> ListingDto:
    try:
        return repository.set_status(listing_id, body.status)
    except ListingNotFound:
        raise ApiError(404, "NOT_FOUND", f"Listing {listing_id} not found") from None
