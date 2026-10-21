"""API DTOs. JSON uses camelCase field names, Python uses snake_case."""

from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic.alias_generators import to_camel


class ListingStatus(StrEnum):
    NEW = "new"
    SAVED = "saved"
    REJECTED = "rejected"


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class ListingDto(CamelModel):
    id: str
    source_id: str | None = None
    title: str
    price: int | None = None
    currency: str
    location: str | None = None
    url: str
    images: list[str]
    description: str | None = None
    status: ListingStatus
    first_seen_at: str
    updated_at: str


class ListingsPageDto(CamelModel):
    items: list[ListingDto]
    page: int
    page_size: int
    total_items: int
    total_pages: int


class CreateListingRequest(CamelModel):
    """Sent by the sync job. The internal id, status and timestamps are set by the API.

    `source_id` is the idempotency key: the source website name plus the listing's ID on
    that website, e.g. "olx:123". A second POST with the same value creates nothing.
    """

    source_id: str = Field(min_length=1, max_length=200)
    title: str
    price: int | None = None
    currency: str = "PLN"
    location: str | None = None
    url: str
    images: list[str]
    description: str | None = None


class UpdateListingStatusRequest(CamelModel):
    status: ListingStatus


class ListingCountsDto(CamelModel):
    new: int
    saved: int
    rejected: int


class ScanJobStatus(StrEnum):
    # Set by POST /scan-job; the sync Lambda has not picked the job up yet.
    CREATED = "created"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class ScanJobDto(CamelModel):
    """A sync run. `created` or `running` for longer than 15 minutes is reported as `failed`."""

    id: str
    status: ScanJobStatus
    created_at: str
    finished_at: str | None = None
    error: str | None = None


class LatestScanDto(CamelModel):
    # Finish time of the newest successful scan; None when none is kept (jobs expire after 3 days).
    last_success_at: str | None = None
    # Scan created or running, so a reloaded UI can keep waiting for it.
    active_job: ScanJobDto | None = None


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


class ErrorDto(CamelModel):
    error: str
    message: str
