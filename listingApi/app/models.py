"""API DTOs. JSON uses camelCase field names, Python uses snake_case."""

from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class ListingStatus(StrEnum):
    NEW = "new"
    SAVED = "saved"
    REJECTED = "rejected"


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class ListingDto(CamelModel):
    id: str
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


class ListingsPageDto(CamelModel):
    items: list[ListingDto]
    page: int
    page_size: int
    total_items: int
    total_pages: int


class CreateListingRequest(CamelModel):
    """Sent by the sync job. The internal id, status and timestamps are set by the API.

    `source_id` is the idempotency key: the source website name plus the listing's ID on
    that website, e.g. "olx:123". A second POST with the same value creates nothing.
    """

    source_id: str = Field(min_length=1, max_length=200)
    title: str
    price: int | None = None
    currency: str = "PLN"
    location: str | None = None
    url: str
    images: list[str]
    description: str | None = None


class UpdateListingStatusRequest(CamelModel):
    status: ListingStatus


class ListingCountsDto(CamelModel):
    new: int
    saved: int
    rejected: int


class ErrorDto(CamelModel):
    error: str
    message: str
