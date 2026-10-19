"""Listings API for the Toaletka UI: app startup. See docs/llstingApi.md.

Run locally: uvicorn app.main:app --port 8000
"""

import boto3
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api_utils import register_error_handlers
from app.endpoints import health_router, listings_router, listings_write_router
from app.repository import ListingRepository
from app.settings import load_settings


def create_app() -> FastAPI:
    settings = load_settings()

    app = FastAPI(title="Toaletka Listings API")
    app.state.settings = settings
    app.state.repository = ListingRepository(boto3.resource("dynamodb").Table(settings.table_name))

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_methods=["GET", "PUT"],
        allow_headers=["Content-Type", "X-API-Key"],
    )
    register_error_handlers(app)
    app.include_router(health_router)
    app.include_router(listings_router)
    app.include_router(listings_write_router)
    return app


app = create_app()
