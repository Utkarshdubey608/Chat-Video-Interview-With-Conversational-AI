"""Shared plumbing for every third-party client.

Gives each vendor module three things so it can be almost pure endpoint mapping:

* a lazily-created shared ``httpx.AsyncClient`` (connection pooling across
  requests, closed once on shutdown),
* ``ProviderNotConfigured`` / ``UpstreamError`` — the two failure modes, turned
  into HTTP responses by the handlers in ``app.main`` so routers need no
  try/except,
* ``ProviderClient.request`` — auth headers applied, errors normalised.

Deliberately not a generic HTTP framework: it exists to keep `gemini.py`,
`tavus.py` and `deepgram.py` readable.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx

from app.config import Settings

logger = logging.getLogger("providers")

# Vendor calls are slower than our own endpoints — Gemini scoring in particular.
# Generous, but never unbounded.
DEFAULT_TIMEOUT = httpx.Timeout(connect=10.0, read=120.0, write=120.0, pool=10.0)

_client: httpx.AsyncClient | None = None
_client_loop: asyncio.AbstractEventLoop | None = None


def http_client() -> httpx.AsyncClient:
    """The shared HTTP client for the running event loop.

    Pooled connections belong to the loop that opened them, so a client reused
    across loops raises "Event loop is closed" when it tries to recycle one.
    Under uvicorn there is a single loop for the process lifetime and this is
    simply a process-wide pool; the loop check only matters where a new loop is
    created per request, which is exactly what `TestClient` does.
    """
    global _client, _client_loop

    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:  # called outside async code — no loop to bind to
        loop = None

    # `_client_loop is None` means the client was injected (tests substituting a
    # MockTransport); leave those alone.
    if _client is not None and not _client.is_closed:
        if _client_loop is None or _client_loop is loop:
            return _client

    _client = httpx.AsyncClient(timeout=DEFAULT_TIMEOUT, follow_redirects=False)
    _client_loop = loop
    return _client


async def aclose() -> None:
    """Release pooled connections. Called from the app's shutdown hook."""
    global _client, _client_loop
    if _client is not None and not _client.is_closed:
        await _client.aclose()
    _client = None
    _client_loop = None


class ProviderNotConfigured(RuntimeError):
    """A provider was used but its key is blank in the environment.

    Surfaces as 503 with an actionable message, so an unset env var never reaches
    the client as a confusing vendor 401.
    """

    def __init__(self, provider: str, env_var: str):
        self.provider = provider
        self.env_var = env_var
        super().__init__(
            f"{provider} is not configured on the server. "
            f"Set {env_var} in the backend environment."
        )


class UpstreamError(RuntimeError):
    """A provider returned an error. Carries enough to build a useful response."""

    def __init__(self, provider: str, status_code: int, detail: str):
        self.provider = provider
        self.status_code = status_code
        self.detail = detail
        super().__init__(f"{provider} returned {status_code}: {detail}")

    @property
    def client_status(self) -> int:
        """The status WE return.

        A vendor 401/403 means OUR key is bad — that is a server-side
        misconfiguration, not something the caller can fix by re-authenticating,
        so it must not be echoed back as 401. Everything else passes through,
        with anything unexpected collapsing to 502.
        """
        if self.status_code in (401, 403):
            return 503
        if self.status_code in (400, 404, 409, 413, 422, 429):
            return self.status_code
        return 502


class ProviderClient:
    """Base for one vendor's API.

    Subclasses set `name`, `env_var`, `base_url`, and implement `auth_headers`.
    """

    name: str = "provider"
    env_var: str = ""
    base_url: str = ""

    def __init__(self, settings: Settings):
        self.settings = settings

    # --- to implement in subclasses -----------------------------------------
    @property
    def api_key(self) -> str:
        raise NotImplementedError

    def auth_headers(self) -> dict[str, str]:
        raise NotImplementedError

    # --- shared behaviour ----------------------------------------------------
    @property
    def is_configured(self) -> bool:
        return bool(self.api_key.strip())

    def require_configured(self) -> None:
        if not self.is_configured:
            raise ProviderNotConfigured(self.name, self.env_var)

    def url(self, path: str) -> str:
        """Absolute URLs pass through; anything else joins onto `base_url`."""
        if path.startswith(("http://", "https://")):
            return path
        return f"{self.base_url.rstrip('/')}/{path.lstrip('/')}"

    async def request(
        self,
        method: str,
        path: str,
        *,
        json: Any | None = None,
        params: dict[str, Any] | None = None,
        content: bytes | None = None,
        files: Any | None = None,
        data: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
        expect_json: bool = True,
    ) -> Any:
        """Call the vendor with auth applied. Raises on any error status.

        `files`/`data` build a multipart body, which one vendor requires (Hume's
        batch submit takes the audio and its job config as two form parts). They
        are mutually exclusive with `json`/`content`; httpx raises if both are
        given, which is the right outcome — it is a programming error.
        """
        self.require_configured()

        response = await http_client().request(
            method,
            self.url(path),
            json=json,
            params=params,
            content=content,
            files=files,
            data=data,
            headers={**self.auth_headers(), **(headers or {})},
        )

        if response.status_code >= 400:
            # Truncated: vendor error bodies can be large, and the full text may
            # echo request content we would rather not put in logs.
            detail = response.text[:500]
            logger.warning("%s %s %s → %s", self.name, method, path, response.status_code)
            raise UpstreamError(self.name, response.status_code, detail)

        if not expect_json:
            return response.content
        if not response.content:
            return {}
        try:
            return response.json()
        except ValueError as exc:
            raise UpstreamError(
                self.name, 502, f"expected JSON, got {response.text[:200]!r}"
            ) from exc
