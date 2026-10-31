"""FastAPI dependencies: the repositories and clients created at startup (app.main)."""

from typing import Annotated

from fastapi import Depends, Request

from app.infra.listing_repository import ListingRepository
from app.infra.scan_job_repository import ScanJobRepository
from app.infra.scan_trigger import ScanTrigger
from app.infra.search_repository import SearchRepository


def get_repository(request: Request) -> ListingRepository:
    return request.app.state.repository


def get_scan_jobs(request: Request) -> ScanJobRepository:
    return request.app.state.scan_jobs


def get_scan_trigger(request: Request) -> ScanTrigger:
    return request.app.state.scan_trigger


def get_searches(request: Request) -> SearchRepository:
    return request.app.state.searches


Repository = Annotated[ListingRepository, Depends(get_repository)]
ScanJobs = Annotated[ScanJobRepository, Depends(get_scan_jobs)]
ScanTriggerDep = Annotated[ScanTrigger, Depends(get_scan_trigger)]
Searches = Annotated[SearchRepository, Depends(get_searches)]
