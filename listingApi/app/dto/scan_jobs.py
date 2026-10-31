"""Scan job request and response bodies. See docs/llstingApi.md, section Scan jobs."""

from pydantic import Field, field_validator

from app.core.scan_job import LatestScan, ScanJob, ScanJobStatus
from app.dto.common import CamelModel


class ScanJobDto(CamelModel):
    """A sync run. `created` or `running` for longer than 15 minutes is reported as `failed`."""

    id: str
    status: ScanJobStatus
    created_at: str
    finished_at: str | None = None
    error: str | None = None

    @classmethod
    def from_core(cls, job: ScanJob) -> "ScanJobDto":
        return cls(
            id=job.id,
            status=job.status,
            created_at=job.created_at,
            finished_at=job.finished_at,
            error=job.error,
        )


class LatestScanDto(CamelModel):
    # Finish time of the newest successful scan; None when none is kept (jobs expire after 3 days).
    last_success_at: str | None = None
    # Scan created or running, so a reloaded UI can keep waiting for it.
    active_job: ScanJobDto | None = None

    @classmethod
    def from_core(cls, latest: LatestScan) -> "LatestScanDto":
        return cls(
            last_success_at=latest.last_success_at,
            active_job=ScanJobDto.from_core(latest.active_job) if latest.active_job else None,
        )


class ReportScanJobRequest(CamelModel):
    """Sent by the sync job when a run starts and when it ends. `created` is set only by the API."""

    status: ScanJobStatus
    error: str | None = Field(default=None, max_length=1000)

    @field_validator("status")
    @classmethod
    def not_created(cls, status: ScanJobStatus) -> ScanJobStatus:
        if status is ScanJobStatus.CREATED:
            raise ValueError("must be running, succeeded or failed")
        return status
