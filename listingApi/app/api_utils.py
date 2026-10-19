"""Shared API pieces: error type and handlers, API key check, repository dependency."""

import secrets
from typing import Annotated

from fastapi import Depends, FastAPI, Header, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.models import ErrorDto
from app.repository import ListingRepository


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


def require_api_key(request: Request, x_api_key: Annotated[str | None, Header()] = None) -> None:
    expected: str = request.app.state.settings.api_key
    if x_api_key is None or not secrets.compare_digest(x_api_key, expected):
        raise ApiError(401, "UNAUTHORIZED", "Missing or invalid X-API-Key header")


def get_repository(request: Request) -> ListingRepository:
    return request.app.state.repository


Repository = Annotated[ListingRepository, Depends(get_repository)]
