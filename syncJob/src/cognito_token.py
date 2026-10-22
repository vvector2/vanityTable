"""Cognito access token for the Listings API, from the client credentials flow.

The sync job's machine client (Terraform module sync_job) may only ask for `listings/create`.
The token is cached and fetched again shortly before it expires.
"""

import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request

from listing_api_client import TRANSIENT_STATUSES, USER_AGENT, ListingApiError, read_error_body

# Fetch a new token this many seconds before the old one expires.
EXPIRY_MARGIN_SECONDS = 60


class TokenProvider:
    def __init__(
        self, token_url: str, client_id: str, client_secret: str, scope: str, timeout: float = 10.0
    ) -> None:
        self._token_url = token_url
        self._auth = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
        self._scope = scope
        self._timeout = timeout
        self._token: str | None = None
        self._expires_at = 0.0

    def __call__(self) -> str:
        """Returns a valid access token. Raises ListingApiError when Cognito does not issue one."""
        if self._token is None or time.monotonic() >= self._expires_at:
            self._token, expires_in = self._fetch()
            self._expires_at = time.monotonic() + max(0, expires_in - EXPIRY_MARGIN_SECONDS)
        return self._token

    def _fetch(self) -> tuple[str, int]:
        request = urllib.request.Request(
            self._token_url,
            data=urllib.parse.urlencode({"grant_type": "client_credentials", "scope": self._scope}).encode(),
            method="POST",
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
                "Authorization": f"Basic {self._auth}",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                body = json.load(response)
        except urllib.error.HTTPError as error:
            raise ListingApiError(
                f"token: HTTP {error.code}: {read_error_body(error)}",
                status=error.code,
                transient=error.code in TRANSIENT_STATUSES,
            ) from error
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            reason = getattr(error, "reason", error)
            raise ListingApiError(f"token: request failed: {reason}", transient=True) from error
        return body["access_token"], int(body.get("expires_in", 3600))
