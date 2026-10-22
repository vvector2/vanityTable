"""Shared API pieces: error type and handlers, repository dependencies."""

from typing import Annotated

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.models import ErrorDto
from app.repository import ListingRepository
from app.scan_jobs import ScanJobRepository
from app.scan_trigger import ScanTrigger


class ApiError(Exception):
    def __init__(self, status_code: int, error: str, message: str) -> None:
        self.status_code = status_code
        self.error = error
        self.message = message


def error_response(status_code: int, error: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=status_code, content=ErrorDto(error=error, message=message).model_dump())


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    def handle_api_error(_: Request, error: ApiError) -> JSONResponse:
        return error_response(error.status_code, error.error, error.message)

    @app.exception_handler(RequestValidationError)
    def handle_validation_error(_: Request, error: RequestValidationError) -> JSONResponse:
        message = "; ".join(
            f"{'.'.join(str(part) for part in e['loc'])}: {e['msg']}" for e in error.errors()
        )
        return error_response(400, "VALIDATION_ERROR", message)


def get_repository(request: Request) -> ListingRepository:
    return request.app.state.repository


Repository = Annotated[ListingRepository, Depends(get_repository)]


def get_scan_jobs(request: Request) -> ScanJobRepository:
    return request.app.state.scan_jobs


def get_scan_trigger(request: Request) -> ScanTrigger:
    return request.app.state.scan_trigger


ScanJobs = Annotated[ScanJobRepository, Depends(get_scan_jobs)]
ScanTriggerDep = Annotated[ScanTrigger, Depends(get_scan_trigger)]
