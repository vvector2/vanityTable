"""Scan job domain model: one per sync run, manual or scheduled. See docs/llstingApi.md, section Scan jobs.

A job still `created` or `running` after JOB_TIMEOUT is reported as `failed`: the Lambda timeout is
15 minutes, so such a run was killed before it could report.
"""

from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from enum import StrEnum


class ScanJobStatus(StrEnum):
    # Set by POST /scan-job; the sync Lambda has not picked the job up yet.
    CREATED = "created"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


JOB_TIMEOUT = timedelta(minutes=15)
# Not finished yet: blocks a new manual scan until it ends or times out.
ACTIVE = (ScanJobStatus.CREATED, ScanJobStatus.RUNNING)
TIMED_OUT_ERROR = "No result within 15 minutes"


@dataclass(frozen=True)
class ScanJob:
    id: str
    status: ScanJobStatus
    created_at: str
    finished_at: str | None = None
    error: str | None = None

    def as_of(self, now: datetime) -> "ScanJob":
        """The job as seen at `now`: still active after JOB_TIMEOUT means it failed."""
        if self.status in ACTIVE and datetime.fromisoformat(self.created_at) <= now - JOB_TIMEOUT:
            return replace(self, status=ScanJobStatus.FAILED, error=TIMED_OUT_ERROR)
        return self


@dataclass(frozen=True)
class LatestScan:
    # Finish time of the newest successful scan; None when none is kept (jobs expire after 3 days).
    last_success_at: str | None
    # Scan created or running, so a reloaded UI can keep waiting for it.
    active_job: ScanJob | None
