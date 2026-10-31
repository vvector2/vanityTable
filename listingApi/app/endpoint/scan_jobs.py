"""/scan-job endpoints. See docs/llstingApi.md, section Scan jobs.

Endpoints convert between DTOs and app.core classes; the handlers do the work.
"""

from typing import Annotated

from fastapi import APIRouter, Path, Response

from app.api_layer.dependencies import ScanJobs, ScanTriggerDep
from app.dto.scan_jobs import LatestScanDto, ReportScanJobRequest, ScanJobDto
from app.endpoint.scopes import create, decide, read
from app.handlers import scan_jobs as handlers

# GET and POST are used by the UI; PUT by the sync job.
scan_job_router = APIRouter(prefix="/scan-job")


@scan_job_router.post(
    "", response_model=ScanJobDto, status_code=201, dependencies=[decide]
)
def start_scan_job(scan_jobs: ScanJobs, trigger: ScanTriggerDep, response: Response) -> ScanJobDto:
    """Starts a scan. While one is active it is returned instead (200), so OLX sees one run at a time."""
    job, started = handlers.start(scan_jobs, trigger)
    if not started:
        response.status_code = 200
    return ScanJobDto.from_core(job)


# Declared before /{job_id}, so "latest" is not read as a job id.
@scan_job_router.get("/latest", response_model=LatestScanDto, dependencies=[read])
def latest_scan(scan_jobs: ScanJobs) -> LatestScanDto:
    return LatestScanDto.from_core(handlers.latest(scan_jobs))


@scan_job_router.get("/{job_id}", response_model=ScanJobDto, dependencies=[read])
def get_scan_job(job_id: str, scan_jobs: ScanJobs) -> ScanJobDto:
    return ScanJobDto.from_core(handlers.get(scan_jobs, job_id))


@scan_job_router.put(
    "/{job_id}", response_model=ScanJobDto, dependencies=[create]
)
def report_scan_job(
    job_id: Annotated[str, Path(min_length=1, max_length=100)],
    body: ReportScanJobRequest,
    scan_jobs: ScanJobs,
) -> ScanJobDto:
    return ScanJobDto.from_core(handlers.report(scan_jobs, job_id, body.status, body.error))
