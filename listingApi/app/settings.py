"""Settings read from environment variables. See docs/llstingApi.md, section Lightsail."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    table_name: str
    api_key: str
    allowed_origins: list[str]


def load_settings() -> Settings:
    api_key = os.environ.get("API_KEY", "")
    if not api_key:
        raise RuntimeError("API_KEY must be set")
    origins = os.environ.get("ALLOWED_ORIGINS", "")
    return Settings(
        table_name=os.environ.get("TABLE_NAME", "Listings"),
        api_key=api_key,
        allowed_origins=[o.strip() for o in origins.split(",") if o.strip()],
    )
