"""/listings endpoints. See docs/llstingApi.md, section Endpoints.

Endpoints convert between DTOs and app.core classes; the handlers do the work.
"""

from typing import Annotated

from fastapi import APIRouter, Query, Response

from app.api_layer.dependencies import Repository, Searches
from app.core.listing import ListingStatus
from app.dto.listings import (
    CreateListingRequest,
    ListingCountsDto,
    ListingDto,
    ListingsPageDto,
    UpdateListingStatusRequest,
)
from app.endpoint.scopes import admin, create, decide, read
from app.handlers import listings

listings_router = APIRouter(prefix="/listings")
# Not used by the UI, so these take the sync job's and the admin's scopes.
listings_write_router = APIRouter(prefix="/listings")

SearchId = Annotated[str, Query(alias="searchId", min_length=1, max_length=100)]


@listings_router.get("", response_model=ListingsPageDto, dependencies=[read])
def list_listings(
    repository: Repository,
    search_id: SearchId,
    status: ListingStatus,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(alias="pageSize", ge=1, le=50)] = 20,
) -> ListingsPageDto:
    return ListingsPageDto.from_core(listings.list_page(repository, search_id, status, page, page_size))


@listings_router.get("/counts", response_model=ListingCountsDto, dependencies=[read])
def listing_counts(repository: Repository, search_id: SearchId) -> ListingCountsDto:
    return ListingCountsDto.from_core(listings.counts(repository, search_id))


@listings_router.put("/{listing_id}/status", response_model=ListingDto, dependencies=[decide])
def update_listing_status(
    listing_id: str, body: UpdateListingStatusRequest, repository: Repository
) -> ListingDto:
    return ListingDto.from_core(listings.set_status(repository, listing_id, body.status))


@listings_write_router.post(
    "",
    response_model=ListingDto,
    status_code=201,
    dependencies=[create],
)
def create_listing(body: CreateListingRequest, repository: Repository, searches: Searches) -> ListingDto:
    return ListingDto.from_core(listings.create(repository, searches, body.to_core()))


@listings_write_router.delete(
    "/{listing_id}", status_code=204, dependencies=[admin]
)
def delete_listing(listing_id: str, repository: Repository) -> Response:
    listings.delete(repository, listing_id)
    return Response(status_code=204)
