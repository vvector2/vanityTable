"""Search request and response bodies. See docs/llstingApi.md, section DTOs, and
docs/SeachCriteria.Feature.md. Validation lives here; app.core holds the plain classes."""

from typing import Annotated

from pydantic import Field, StringConstraints, model_validator

from app.core.search import Criteria, Location, NewSearch, SearchOverview, SearchStatus
from app.dto.common import CamelModel
from app.dto.listings import ListingCountsDto

Keyword = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=50)]


class LocationDto(CamelModel):
    city: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    radius_km: int | None = Field(default=None, ge=0)

    @classmethod
    def from_core(cls, location: Location) -> "LocationDto":
        return cls(city=location.city, radius_km=location.radius_km)

    def to_core(self) -> Location:
        return Location(city=self.city, radius_km=self.radius_km)


class CriteriaDto(CamelModel):
    """Filter of a search. See docs/SeachCriteria.Feature.md, section 4. Prices are in PLN."""

    keywords: list[Keyword] = Field(min_length=1, max_length=10)
    exclude_keywords: list[Keyword] = Field(default_factory=list, max_length=10)
    price_min: int | None = Field(default=None, ge=0)
    price_max: int | None = Field(default=None, ge=0)
    location: LocationDto | None = None
    # Displayed only; not used for matching until the AI feature.
    description: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def price_range(self) -> "CriteriaDto":
        if self.price_min is not None and self.price_max is not None and self.price_min > self.price_max:
            raise ValueError("priceMin must not be greater than priceMax")
        return self

    @classmethod
    def from_core(cls, criteria: Criteria) -> "CriteriaDto":
        return cls(
            keywords=criteria.keywords,
            exclude_keywords=criteria.exclude_keywords,
            price_min=criteria.price_min,
            price_max=criteria.price_max,
            location=LocationDto.from_core(criteria.location) if criteria.location else None,
            description=criteria.description,
        )

    def to_core(self) -> Criteria:
        return Criteria(
            keywords=list(self.keywords),
            exclude_keywords=list(self.exclude_keywords),
            price_min=self.price_min,
            price_max=self.price_max,
            location=self.location.to_core() if self.location else None,
            description=self.description,
        )


class SearchDto(CamelModel):
    id: str
    title: str
    criteria: CriteriaDto
    status: SearchStatus
    counts: ListingCountsDto
    created_at: str
    updated_at: str

    @classmethod
    def from_core(cls, overview: SearchOverview) -> "SearchDto":
        search = overview.search
        return cls(
            id=search.id,
            title=search.title,
            criteria=CriteriaDto.from_core(search.criteria),
            status=search.status,
            counts=ListingCountsDto.from_core(overview.counts),
            created_at=search.created_at,
            updated_at=search.updated_at,
        )


class CreateSearchRequest(CamelModel):
    """Sent by the UI. The API sets the id, the user id (token `sub`), `status=active` and the dates."""

    title: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]
    criteria: CriteriaDto

    def to_core(self) -> NewSearch:
        return NewSearch(title=self.title, criteria=self.criteria.to_core())
