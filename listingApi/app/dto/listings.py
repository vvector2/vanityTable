"""Listing request and response bodies. See docs/llstingApi.md, section DTOs.

DTOs are only the wire format; handlers work with app.core classes. Requests convert with
`to_core()`, responses are built with `from_core()`.
"""

from pydantic import Field

from app.core.listing import Listing, ListingCounts, ListingsPage, ListingStatus, NewListing
from app.dto.common import CamelModel


class ListingDto(CamelModel):
    id: str
    search_id: str | None = None
    source_id: str | None = None
    title: str
    price: int | None = None
    currency: str
    location: str | None = None
    url: str
    images: list[str]
    description: str | None = None
    status: ListingStatus
    first_seen_at: str
    updated_at: str

    @classmethod
    def from_core(cls, listing: Listing) -> "ListingDto":
        return cls(
            id=listing.id,
            search_id=listing.search_id,
            source_id=listing.source_id,
            title=listing.title,
            price=listing.price,
            currency=listing.currency,
            location=listing.location,
            url=listing.url,
            images=listing.images,
            description=listing.description,
            status=listing.status,
            first_seen_at=listing.first_seen_at,
            updated_at=listing.updated_at,
        )


class ListingsPageDto(CamelModel):
    items: list[ListingDto]
    page: int
    page_size: int
    total_items: int
    total_pages: int

    @classmethod
    def from_core(cls, page: ListingsPage) -> "ListingsPageDto":
        return cls(
            items=[ListingDto.from_core(listing) for listing in page.items],
            page=page.page,
            page_size=page.page_size,
            total_items=page.total_items,
            total_pages=page.total_pages,
        )


class CreateListingRequest(CamelModel):
    """Sent by the sync job. The internal id, status and timestamps are set by the API.

    `search_id` plus `source_id` is the idempotency key. `source_id` is the source website
    name plus the listing's ID on that website, e.g. "olx:123". A second POST with the same
    pair creates nothing; the same ad in another search is a separate listing.
    """

    search_id: str = Field(min_length=1, max_length=100)
    source_id: str = Field(min_length=1, max_length=200)
    title: str
    price: int | None = None
    currency: str = "PLN"
    location: str | None = None
    url: str
    images: list[str]
    description: str | None = None

    def to_core(self) -> NewListing:
        return NewListing(
            search_id=self.search_id,
            source_id=self.source_id,
            title=self.title,
            url=self.url,
            images=list(self.images),
            price=self.price,
            currency=self.currency,
            location=self.location,
            description=self.description,
        )


class UpdateListingStatusRequest(CamelModel):
    status: ListingStatus


class ListingCountsDto(CamelModel):
    new: int
    saved: int
    rejected: int

    @classmethod
    def from_core(cls, counts: ListingCounts) -> "ListingCountsDto":
        return cls(new=counts.new, saved=counts.saved, rejected=counts.rejected)
