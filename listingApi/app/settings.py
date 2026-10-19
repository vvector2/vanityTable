"""Settings read from environment variables. See docs/llstingApi.md, section Lightsail."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    table_name: str
    api_key: str
    # Optional: when unset, the endpoints that need them reject every request.
    sync_api_key: str | None
    admin_api_key: str | None
    allowed_origins: list[str]


def load_settings() -> Settings:
    api_key = os.environ.get("API_KEY", "")
    if not api_key:
        raise RuntimeError("API_KEY must be set")
    origins = os.environ.get("ALLOWED_ORIGINS", "")
    return Settings(
        table_name=os.environ.get("TABLE_NAME", "Listings"),
        api_key=api_key,
        sync_api_key=os.environ.get("SYNC_API_KEY") or None,
        admin_api_key=os.environ.get("ADMIN_API_KEY") or None,
        allowed_origins=[o.strip() for o in origins.split(",") if o.strip()],
    )
