"""Settings read from environment variables. See docs/llstingApi.md, section Lightsail."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    table_name: str
    # boto3 reads only AWS_DEFAULT_REGION outside Lambda, so AWS_REGION is passed explicitly.
    region: str | None
    # Cognito user pool that issues the access tokens, e.g. https://cognito-idp.<region>.amazonaws.com/<pool id>.
    cognito_issuer: str
    # Resource server identifier; scopes are <prefix>/read, /decide, /create and /admin.
    scope_prefix: str
    allowed_origins: list[str]
    scan_jobs_table_name: str
    # Sync Lambda that POST /scan-job invokes. Unset: POST /scan-job only records the job.
    scan_function_name: str | None


def load_settings() -> Settings:
    cognito_issuer = os.environ.get("COGNITO_ISSUER", "")
    if not cognito_issuer:
        raise RuntimeError("COGNITO_ISSUER must be set")
    origins = os.environ.get("ALLOWED_ORIGINS", "")
    return Settings(
        table_name=os.environ.get("TABLE_NAME", "Listings"),
        region=os.environ.get("AWS_REGION") or None,
        cognito_issuer=cognito_issuer,
        scope_prefix=os.environ.get("COGNITO_SCOPE_PREFIX") or "listings",
        allowed_origins=[o.strip() for o in origins.split(",") if o.strip()],
        scan_jobs_table_name=os.environ.get("SCAN_JOBS_TABLE_NAME", "ScanJobs"),
        scan_function_name=os.environ.get("SCAN_FUNCTION_NAME") or None,
    )
