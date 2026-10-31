"""Scan job use cases behind the /scan-job endpoints. See docs/llstingApi.md, section Scan jobs.

They take and return app.core classes."""

from app.api_layer.errors import ApiError
from app.core.scan_job import LatestScan, ScanJob, ScanJobStatus
from app.infra.scan_job_repository import ScanJobNotFound, ScanJobRepository
from app.infra.scan_trigger import ScanTrigger, ScanTriggerFailed


def start(scan_jobs: ScanJobRepository, trigger: ScanTrigger) -> tuple[ScanJob, bool]:
    """Starts a scan and returns it with True. While one is active it is returned instead, with
    False, so OLX sees one run at a time."""
    active = scan_jobs.find_active()
    if active:
        return active, False
    job = scan_jobs.create()
    try:
        trigger.request_scan(job.id)
    except ScanTriggerFailed as error:
        scan_jobs.report(job.id, ScanJobStatus.FAILED, f"Could not start the scan: {error}")
        raise ApiError(502, "SCAN_NOT_STARTED", "Could not start the scan") from error
    return job, True


def latest(scan_jobs: ScanJobRepository) -> LatestScan:
    succeeded = scan_jobs.latest_succeeded()
    return LatestScan(
        last_success_at=succeeded.finished_at if succeeded else None,
        active_job=scan_jobs.find_active(),
    )


def get(scan_jobs: ScanJobRepository, job_id: str) -> ScanJob:
    try:
        return scan_jobs.get(job_id)
    except ScanJobNotFound:
        raise ApiError(404, "NOT_FOUND", f"Scan job {job_id} not found") from None


def report(scan_jobs: ScanJobRepository, job_id: str, status: ScanJobStatus, error: str | None) -> ScanJob:
    """Status from the sync job. Unknown ids are created: scheduled runs report under their own id."""
    return scan_jobs.report(job_id, status, error)
