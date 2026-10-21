"""Settings read from environment variables. See docs/llstingApi.md, section Lightsail."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    table_name: str
    # boto3 reads only AWS_DEFAULT_REGION outside Lambda, so AWS_REGION is passed explicitly.
    region: str | None
    api_key: str
    # Optional: when unset, the endpoints that need them reject every request.
    sync_api_key: str | None
    admin_api_key: str | None
    allowed_origins: list[str]
    scan_jobs_table_name: str
    # Sync Lambda that POST /scan-job invokes. Unset: POST /scan-job only records the job.
    scan_function_name: str | None


def load_settings() -> Settings:
    api_key = os.environ.get("API_KEY", "")
    if not api_key:
        raise RuntimeError("API_KEY must be set")
    origins = os.environ.get("ALLOWED_ORIGINS", "")
    return Settings(
        table_name=os.environ.get("TABLE_NAME", "Listings"),
        region=os.environ.get("AWS_REGION") or None,
        api_key=api_key,
        sync_api_key=os.environ.get("SYNC_API_KEY") or None,
        admin_api_key=os.environ.get("ADMIN_API_KEY") or None,
        allowed_origins=[o.strip() for o in origins.split(",") if o.strip()],
        scan_jobs_table_name=os.environ.get("SCAN_JOBS_TABLE_NAME", "ScanJobs"),
        scan_function_name=os.environ.get("SCAN_FUNCTION_NAME") or None,
    )
