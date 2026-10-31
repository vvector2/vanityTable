"""Listing domain model. Plain classes: no FastAPI, pydantic or DynamoDB here."""

import math
import uuid
from dataclasses import dataclass
from enum import StrEnum

# Fixed namespace for listing ids. Changing it would give known listings new ids.
LISTING_ID_NAMESPACE = uuid.UUID("5b0f6d2e-8c7a-4e1b-9a3d-2f4c6e8a1b0d")


class ListingStatus(StrEnum):
    NEW = "new"
    SAVED = "saved"
    REJECTED = "rejected"


def listing_id_for(search_id: str, source_id: str) -> str:
    """Internal id of a listing, derived from its search and source id.

    Deterministic, so the same pair always maps to the same listing and a second create of it
    can be refused. The same ad in two searches gets two ids, so each search keeps its own status.
    """
    return str(uuid.uuid5(LISTING_ID_NAMESPACE, f"{search_id}:{source_id}"))


@dataclass(frozen=True)
class NewListing:
    """A listing found by the sync job, before it is stored.

    `source_id` is the source website name plus the listing's ID on that website, e.g. "olx:123".
    """

    search_id: str
    source_id: str
    title: str
    url: str
    images: list[str]
    price: int | None = None
    currency: str = "PLN"
    location: str | None = None
    description: str | None = None

    @property
    def id(self) -> str:
        return listing_id_for(self.search_id, self.source_id)


@dataclass(frozen=True)
class Listing:
    id: str
    # None only for listings stored before searches existed.
    search_id: str | None
    source_id: str | None
    title: str
    price: int | None
    currency: str
    location: str | None
    url: str
    images: list[str]
    description: str | None
    status: ListingStatus
    first_seen_at: str
    updated_at: str


@dataclass(frozen=True)
class ListingCounts:
    new: int
    saved: int
    rejected: int

    @classmethod
    def empty(cls) -> "ListingCounts":
        return cls(new=0, saved=0, rejected=0)


@dataclass(frozen=True)
class ListingsPage:
    items: list[Listing]
    page: int
    page_size: int
    total_items: int

    @property
    def total_pages(self) -> int:
        return math.ceil(self.total_items / self.page_size)
