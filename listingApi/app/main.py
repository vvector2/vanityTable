"""Listings API for the Toaletka UI: app startup. See docs/llstingApi.md.

Run locally: uvicorn app.main:app --port 8000
"""

import boto3
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api_utils import register_error_handlers
from app.auth import TokenVerifier
from app.endpoints import health_router, listings_router, listings_write_router, scan_job_router
from app.repository import ListingRepository
from app.scan_jobs import ScanJobRepository
from app.scan_trigger import ScanTrigger
from app.settings import load_settings


def create_app() -> FastAPI:
    settings = load_settings()

    app = FastAPI(title="Toaletka Listings API")
    app.state.settings = settings
    app.state.token_verifier = TokenVerifier(settings.cognito_issuer)
    dynamodb = boto3.resource("dynamodb", region_name=settings.region)
    app.state.repository = ListingRepository(dynamodb.Table(settings.table_name))
    app.state.scan_jobs = ScanJobRepository(dynamodb.Table(settings.scan_jobs_table_name))
    app.state.scan_trigger = ScanTrigger(
        boto3.client("lambda", region_name=settings.region), settings.scan_function_name
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_methods=["GET", "PUT", "POST"],
        allow_headers=["Content-Type", "Authorization"],
    )
    register_error_handlers(app)
    app.include_router(health_router)
    app.include_router(listings_router)
    app.include_router(listings_write_router)
    app.include_router(scan_job_router)
    return app


app = create_app()
