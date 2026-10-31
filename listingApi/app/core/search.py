"""Search domain model. See docs/SeachCriteria.Feature.md. Plain classes, no framework code."""

from dataclasses import dataclass, field
from enum import StrEnum

from app.core.listing import ListingCounts


class SearchStatus(StrEnum):
    # Only status for now; pausing comes later.
    ACTIVE = "active"


@dataclass(frozen=True)
class Location:
    city: str
    radius_km: int | None = None


@dataclass(frozen=True)
class Criteria:
    """Filter of a search. Prices are in PLN."""

    keywords: list[str]
    exclude_keywords: list[str] = field(default_factory=list)
    price_min: int | None = None
    price_max: int | None = None
    location: Location | None = None
    # Displayed only; not used for matching until the AI feature.
    description: str | None = None


@dataclass(frozen=True)
class NewSearch:
    """A search the user asked for, before it is stored."""

    title: str
    criteria: Criteria


@dataclass(frozen=True)
class Search:
    id: str
    # Cognito `sub` of the owner.
    user_id: str
    title: str
    criteria: Criteria
    status: SearchStatus
    created_at: str
    updated_at: str


@dataclass(frozen=True)
class SearchOverview:
    """A search with its listing counts per status, as the home screen shows it."""

    search: Search
    counts: ListingCounts
