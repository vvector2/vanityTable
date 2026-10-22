"""Cognito access token checks. See docs/llstingApi.md, section Auth.

Every endpoint except /health needs `Authorization: Bearer <access token>` issued by the
Cognito user pool, carrying the endpoint's scope (`<prefix>/read`, `/decide`, `/create`, `/admin`).
"""

from collections.abc import Callable
from typing import Annotated, Any

import jwt
from fastapi import Header, Request

from app.api_utils import ApiError


class InvalidToken(Exception):
    pass


class TokenVerifier:
    """Checks a Cognito access token's signature, expiry, issuer and type, and returns its scopes."""

    def __init__(self, issuer: str, jwks_client: jwt.PyJWKClient | None = None) -> None:
        self._issuer = issuer.rstrip("/")
        # PyJWKClient caches the pool's signing keys, so JWKS is fetched once per key id.
        self._jwks = jwks_client or jwt.PyJWKClient(f"{self._issuer}/.well-known/jwks.json")

    def scopes(self, token: str) -> set[str]:
        try:
            key = self._jwks.get_signing_key_from_jwt(token).key
            # Cognito access tokens have no `aud`; the client is in `client_id`.
            claims: dict[str, Any] = jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                issuer=self._issuer,
                options={"require": ["exp", "iss", "token_use"], "verify_aud": False},
            )
        except jwt.PyJWTError as error:
            raise InvalidToken(str(error)) from error
        if claims.get("token_use") != "access":
            raise InvalidToken("Not an access token")
        return set(str(claims.get("scope", "")).split())


def require_scope(scope: str) -> Callable[..., None]:
    """Dependency: 401 without a valid token, 403 when the token lacks `<prefix>/<scope>`."""

    def check(request: Request, authorization: Annotated[str | None, Header()] = None) -> None:
        scheme, _, token = (authorization or "").partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise ApiError(401, "UNAUTHORIZED", "Missing bearer token")
        try:
            scopes = request.app.state.token_verifier.scopes(token)
        except InvalidToken:
            raise ApiError(401, "UNAUTHORIZED", "Invalid or expired token") from None
        required = f"{request.app.state.settings.scope_prefix}/{scope}"
        if required not in scopes:
            raise ApiError(403, "FORBIDDEN", f"Token lacks scope {required}")

    return check
