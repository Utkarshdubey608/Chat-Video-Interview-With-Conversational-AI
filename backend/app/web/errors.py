"""Response-shape compatibility for the web client.

The Express server answered every failure as `{"error": "..."}` (see its
`errorHandler` in `server/index.ts`), and the web client reads exactly that key:

    const message = (data && (data.error as string)) || `Request failed (${res.status})`
    — web_version/talbotiq-platform/src/lib/api.ts

FastAPI answers `{"detail": "..."}`. Left alone, every error message the
recruiter sees would degrade to "Request failed (400)".

So these handlers emit **both** keys for `/api/web/*` responses. Both rather than
a rename because the Flutter app reads `detail`, and one shared handler must not
break it — `BackendException` and `ApiException` both parse that field.

Scoped by path prefix, so nothing outside `/api/web/*` changes shape.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exception_handlers import (
    http_exception_handler,
    request_validation_exception_handler,
)
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.firebase import FirestoreUnavailable

logger = logging.getLogger("web.errors")

WEB_PREFIX = "/api/web"


def _is_web(request: Request) -> bool:
    return request.url.path.startswith(WEB_PREFIX)


def _both(status_code: int, message: str, headers: dict | None = None) -> JSONResponse:
    """A body carrying the message under both keys."""
    return JSONResponse(
        status_code=status_code,
        content={"error": message, "detail": message},
        headers=headers,
    )


def register(app: FastAPI) -> None:
    """Install the web surface's error handlers.

    Called by `app.web.install`, not from `app.main` directly, so adding or
    removing a handler never touches the application entrypoint.
    """

    @app.exception_handler(FirestoreUnavailable)
    async def _store_unavailable(request: Request, exc: FirestoreUnavailable):
        # 503, not 500: the service is healthy, it just has no credentials. The
        # message names the missing environment variable, so it is safe and
        # useful to return — it describes OUR configuration, not the request.
        logger.error("Firestore unavailable for %s: %s", request.url.path, exc)
        message = f"Storage is unavailable: {exc}"
        if _is_web(request):
            return _both(503, message)
        return JSONResponse(status_code=503, content={"detail": message})

    # Registered against STARLETTE's HTTPException, not FastAPI's. Handler lookup
    # walks the raised class's MRO, and FastAPI's is a subclass of Starlette's —
    # so registering the subclass would catch exceptions raised inside route
    # handlers but miss the ones Starlette's own router raises: the 404 for an
    # unknown path and the 405 for a wrong method. Registering the base catches
    # both.
    @app.exception_handler(HTTPException)
    async def _http(request: Request, exc: HTTPException):
        if not _is_web(request):
            # Untouched for the mobile/desktop surface.
            return await http_exception_handler(request, exc)
        detail = exc.detail if isinstance(exc.detail, str) else "Request failed."
        return _both(exc.status_code, detail, headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _validation(request: Request, exc: RequestValidationError):
        if not _is_web(request):
            return await request_validation_exception_handler(request, exc)
        # The client shows this string to a recruiter, so it names the offending
        # field rather than dumping pydantic's nested error structure. The raw
        # errors are logged instead, where a developer can still reach them.
        logger.info("validation failed for %s: %s", request.url.path, exc.errors())
        return _both(422, _first_validation_message(exc))


def _first_validation_message(exc: RequestValidationError) -> str:
    """A one-line, human-readable version of the first validation failure.

    Pure and exported for tests: the exact wording is what a recruiter reads.
    """
    errors = exc.errors()
    if not errors:
        return "Invalid request."

    first = errors[0]
    # loc is like ("body", "recipients", 0, "email"); "body" is noise to a user.
    parts = [str(p) for p in first.get("loc", ()) if p not in ("body", "query", "path")]
    field = ".".join(parts)
    message = str(first.get("msg") or "is invalid")
    return f"{field}: {message}" if field else message
