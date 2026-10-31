"""Cognito access token checks. See docs/llstingApi.md, section Auth.

Every endpoint except /health needs `Authorization: Bearer <access token>` issued by the
Cognito user pool, carrying the endpoint's scope: `<prefix>/read`, `/decide`, `/create`, `/admin`
for listings and scan jobs, `<searches prefix>/read`, `/write` for searches.
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Annotated, Any, Literal

import jwt
from fastapi import Depends, Header, Request

from app.api_layer.errors import ApiError


# Seconds of clock skew allowed on `iat` and `exp`. Without it a fresh token is rejected as not yet
# valid when this machine's clock is even slightly behind Cognito's.
CLOCK_SKEW_SECONDS = 30


class InvalidToken(Exception):
    pass


@dataclass(frozen=True)
class Principal:
    # Cognito `sub`: the user for UI tokens, the app client for client credentials tokens.
    subject: str
    scopes: set[str]


class TokenVerifier:
    """Checks a Cognito access token's signature, expiry, issuer and type, and returns its caller."""

    def __init__(self, issuer: str, jwks_client: jwt.PyJWKClient | None = None) -> None:
        self._issuer = issuer.rstrip("/")
        # PyJWKClient caches the pool's signing keys, so JWKS is fetched once per key id.
        self._jwks = jwks_client or jwt.PyJWKClient(f"{self._issuer}/.well-known/jwks.json")

    def verify(self, token: str) -> Principal:
        try:
            key = self._jwks.get_signing_key_from_jwt(token).key
            # Cognito access tokens have no `aud`; the client is in `client_id`.
            claims: dict[str, Any] = jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                issuer=self._issuer,
                leeway=CLOCK_SKEW_SECONDS,
                options={"require": ["exp", "iss", "sub", "token_use"], "verify_aud": False},
            )
        except jwt.PyJWTError as error:
            raise InvalidToken(str(error)) from error
        if claims.get("token_use") != "access":
            raise InvalidToken("Not an access token")
        return Principal(subject=str(claims["sub"]), scopes=set(str(claims.get("scope", "")).split()))


def require_scope(scope: str, resource: Literal["listings", "searches"] = "listings") -> Callable[..., None]:
    """Dependency: 401 without a valid token, 403 when the token lacks `<prefix>/<scope>`.

    The prefix is the resource server of `resource`. The caller's `sub` is kept in
    `request.state.user_id` for the endpoint (see CurrentUser).
    """

    def check(request: Request, authorization: Annotated[str | None, Header()] = None) -> None:
        scheme, _, token = (authorization or "").partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise ApiError(401, "UNAUTHORIZED", "Missing bearer token")
        try:
            principal = request.app.state.token_verifier.verify(token)
        except InvalidToken:
            raise ApiError(401, "UNAUTHORIZED", "Invalid or expired token") from None
        settings = request.app.state.settings
        prefix = settings.searches_scope_prefix if resource == "searches" else settings.scope_prefix
        required = f"{prefix}/{scope}"
        if required not in principal.scopes:
            raise ApiError(403, "FORBIDDEN", f"Token lacks scope {required}")
        request.state.user_id = principal.subject

    return check


def get_user_id(request: Request) -> str:
    """`sub` of the token checked by require_scope, which must run first (route dependencies do)."""
    return request.state.user_id


CurrentUser = Annotated[str, Depends(get_user_id)]
