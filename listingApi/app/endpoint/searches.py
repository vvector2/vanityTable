"""/searches endpoints. See docs/llstingApi.md, section Endpoints.

Endpoints convert between DTOs and app.core classes; the handlers do the work.
"""

from fastapi import APIRouter, Response

from app.api_layer.auth import CurrentUser
from app.api_layer.dependencies import Repository, Searches
from app.core.search import SearchStatus
from app.dto.searches import CreateSearchRequest, SearchDto
from app.endpoint.scopes import searches_read, searches_write
from app.handlers import searches as handlers

searches_router = APIRouter(prefix="/searches")


@searches_router.get("", response_model=list[SearchDto], dependencies=[searches_read])
def list_searches(
    searches: Searches, repository: Repository, user_id: CurrentUser, status: SearchStatus | None = None
) -> list[SearchDto]:
    return [SearchDto.from_core(found) for found in handlers.list_searches(searches, repository, user_id, status)]


@searches_router.post("", response_model=SearchDto, status_code=201, dependencies=[searches_write])
def create_search(body: CreateSearchRequest, searches: Searches, user_id: CurrentUser) -> SearchDto:
    return SearchDto.from_core(handlers.create(searches, user_id, body.to_core()))


@searches_router.get("/{search_id}", response_model=SearchDto, dependencies=[searches_read])
def get_search(search_id: str, searches: Searches, repository: Repository) -> SearchDto:
    return SearchDto.from_core(handlers.get(searches, repository, search_id))


@searches_router.delete("/{search_id}", status_code=204, dependencies=[searches_write])
def delete_search(search_id: str, searches: Searches, repository: Repository) -> Response:
    handlers.delete(searches, repository, search_id)
    return Response(status_code=204)
