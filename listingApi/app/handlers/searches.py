"""Search use cases behind the /searches endpoints. They take and return app.core classes."""

from app.api_layer.errors import ApiError
from app.core.listing import ListingCounts
from app.core.search import NewSearch, SearchOverview, SearchStatus
from app.infra.listing_repository import ListingRepository
from app.infra.search_repository import SearchNotFound, SearchRepository


def list_searches(
    searches: SearchRepository, listings: ListingRepository, user_id: str, status: SearchStatus | None
) -> list[SearchOverview]:
    """Newest first. Without `status`: the caller's searches (home screen). With `status`: every
    user's searches in that status, for the sync job, whose token belongs to no user."""
    found = searches.list_by_status(status) if status else searches.list_for_user(user_id)
    return [SearchOverview(search, listings.counts(search.id)) for search in found]


def create(searches: SearchRepository, user_id: str, search: NewSearch) -> SearchOverview:
    return SearchOverview(searches.create(user_id, search), ListingCounts.empty())


def get(searches: SearchRepository, listings: ListingRepository, search_id: str) -> SearchOverview:
    try:
        search = searches.get(search_id)
    except SearchNotFound:
        raise ApiError(404, "NOT_FOUND", f"Search {search_id} not found") from None
    return SearchOverview(search, listings.counts(search_id))


def delete(searches: SearchRepository, listings: ListingRepository, search_id: str) -> None:
    """Deletes the listings first, so a failure leaves the search in place and the call can be retried."""
    if not searches.exists(search_id):
        raise ApiError(404, "NOT_FOUND", f"Search {search_id} not found")
    listings.delete_for_search(search_id)
    try:
        searches.delete(search_id)
    except SearchNotFound:
        raise ApiError(404, "NOT_FOUND", f"Search {search_id} not found") from None
