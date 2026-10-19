"""API DTOs. JSON uses camelCase field names, Python uses snake_case."""

from enum import StrEnum

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class ListingStatus(StrEnum):
    NEW = "new"
    SAVED = "saved"
    REJECTED = "rejected"


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class ListingDto(CamelModel):
    id: str
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


class UpdateListingStatusRequest(CamelModel):
    status: ListingStatus


class ListingCountsDto(CamelModel):
    new: int
    saved: int
    rejected: int


class ErrorDto(CamelModel):
    error: str
    message: str
