"""Listing use cases behind the /listings endpoints. They take and return app.core classes."""

from app.api_layer.errors import ApiError
from app.core.listing import Listing, ListingCounts, ListingsPage, ListingStatus, NewListing
from app.infra.listing_repository import ListingAlreadyExists, ListingNotFound, ListingRepository
from app.infra.search_repository import SearchRepository


def list_page(
    repository: ListingRepository, search_id: str, status: ListingStatus, page: int, page_size: int
) -> ListingsPage:
    return ListingsPage(
        items=repository.list_page(search_id, status, page, page_size),
        page=page,
        page_size=page_size,
        total_items=repository.count(search_id, status),
    )


def counts(repository: ListingRepository, search_id: str) -> ListingCounts:
    return repository.counts(search_id)


def set_status(repository: ListingRepository, listing_id: str, status: ListingStatus) -> Listing:
    try:
        return repository.set_status(listing_id, status)
    except ListingNotFound:
        raise ApiError(404, "NOT_FOUND", f"Listing {listing_id} not found") from None


def create(repository: ListingRepository, searches: SearchRepository, listing: NewListing) -> Listing:
    # A search deleted during a sync run would otherwise get its listings back as orphans.
    if not searches.exists(listing.search_id):
        raise ApiError(404, "NOT_FOUND", f"Search {listing.search_id} not found")
    try:
        return repository.create(listing)
    except ListingAlreadyExists:
        raise ApiError(
            409,
            "CONFLICT",
            f"Listing with sourceId {listing.source_id} already exists in search {listing.search_id}",
        ) from None


def delete(repository: ListingRepository, listing_id: str) -> None:
    try:
        repository.delete(listing_id)
    except ListingNotFound:
        raise ApiError(404, "NOT_FOUND", f"Listing {listing_id} not found") from None
