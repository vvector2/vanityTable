"""API endpoints. See docs/llstingApi.md, section Endpoints."""

import math
from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, Response

from app.api_utils import (
    ApiError,
    Repository,
    ScanJobs,
    ScanTriggerDep,
    require_admin_api_key,
    require_api_key,
    require_sync_api_key,
)
from app.models import (
    CreateListingRequest,
    LatestScanDto,
    ListingCountsDto,
    ListingDto,
    ListingsPageDto,
    ListingStatus,
    ReportScanJobRequest,
    ScanJobDto,
    ScanJobStatus,
    UpdateListingStatusRequest,
)
from app.repository import ListingAlreadyExists, ListingNotFound
from app.scan_jobs import ScanJobNotFound
from app.scan_trigger import ScanTriggerFailed

health_router = APIRouter()
listings_router = APIRouter(prefix="/listings", dependencies=[Depends(require_api_key)])
# Not used by the UI, so these take their own keys instead of the UI's API key.
listings_write_router = APIRouter(prefix="/listings")
# GET and POST are used by the UI; PUT by the sync job, so it takes the sync key.
scan_job_router = APIRouter(prefix="/scan-job")


@health_router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@listings_router.get("", response_model=ListingsPageDto)
def list_listings(
    repository: Repository,
    status: ListingStatus,
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(alias="pageSize", ge=1, le=50)] = 20,
) -> ListingsPageDto:
    total_items = repository.count(status)
    return ListingsPageDto(
        items=repository.list_page(status, page, page_size),
        page=page,
        page_size=page_size,
        total_items=total_items,
        total_pages=math.ceil(total_items / page_size),
    )


@listings_router.get("/counts", response_model=ListingCountsDto)
def listing_counts(repository: Repository) -> ListingCountsDto:
    return ListingCountsDto(**{status.value: repository.count(status) for status in ListingStatus})


@listings_router.put("/{listing_id}/status", response_model=ListingDto)
def update_listing_status(
    listing_id: str, body: UpdateListingStatusRequest, repository: Repository
) -> ListingDto:
    try:
        return repository.set_status(listing_id, body.status)
    except ListingNotFound:
        raise ApiError(404, "NOT_FOUND", f"Listing {listing_id} not found") from None


@listings_write_router.post(
    "",
    response_model=ListingDto,
    status_code=201,
    dependencies=[Depends(require_sync_api_key)],
)
def create_listing(body: CreateListingRequest, repository: Repository) -> ListingDto:
    try:
        return repository.create(body)
    except ListingAlreadyExists:
        raise ApiError(409, "CONFLICT", f"Listing with sourceId {body.source_id} already exists") from None


@listings_write_router.delete(
    "/{listing_id}", status_code=204, dependencies=[Depends(require_admin_api_key)]
)
def delete_listing(listing_id: str, repository: Repository) -> Response:
    try:
        repository.delete(listing_id)
    except ListingNotFound:
        raise ApiError(404, "NOT_FOUND", f"Listing {listing_id} not found") from None
    return Response(status_code=204)


@scan_job_router.post(
    "", response_model=ScanJobDto, status_code=201, dependencies=[Depends(require_api_key)]
)
def start_scan_job(scan_jobs: ScanJobs, trigger: ScanTriggerDep, response: Response) -> ScanJobDto:
    """Starts a scan. While one is active it is returned instead (200), so OLX sees one run at a time."""
    active = scan_jobs.find_active()
    if active:
        response.status_code = 200
        return active
    job = scan_jobs.create()
    try:
        trigger.request_scan(job.id)
    except ScanTriggerFailed as error:
        scan_jobs.report(job.id, ScanJobStatus.FAILED, f"Could not start the scan: {error}")
        raise ApiError(502, "SCAN_NOT_STARTED", "Could not start the scan") from error
    return job


# Declared before /{job_id}, so "latest" is not read as a job id.
@scan_job_router.get("/latest", response_model=LatestScanDto, dependencies=[Depends(require_api_key)])
def latest_scan(scan_jobs: ScanJobs) -> LatestScanDto:
    succeeded = scan_jobs.latest_succeeded()
    return LatestScanDto(
        last_success_at=succeeded.finished_at if succeeded else None,
        active_job=scan_jobs.find_active(),
    )


@scan_job_router.get("/{job_id}", response_model=ScanJobDto, dependencies=[Depends(require_api_key)])
def get_scan_job(job_id: str, scan_jobs: ScanJobs) -> ScanJobDto:
    try:
        return scan_jobs.get(job_id)
    except ScanJobNotFound:
        raise ApiError(404, "NOT_FOUND", f"Scan job {job_id} not found") from None


@scan_job_router.put(
    "/{job_id}", response_model=ScanJobDto, dependencies=[Depends(require_sync_api_key)]
)
def report_scan_job(
    job_id: Annotated[str, Path(min_length=1, max_length=100)],
    body: ReportScanJobRequest,
    scan_jobs: ScanJobs,
) -> ScanJobDto:
    """Status from the sync job. Unknown ids are created: scheduled runs report under their own id."""
    return scan_jobs.report(job_id, body.status, body.error)
