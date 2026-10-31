"""Lightsail health check, no token."""

from fastapi import APIRouter

health_router = APIRouter()


@health_router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
