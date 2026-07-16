"""API-key auth.

The Flutter app sends a shared secret as `X-API-Key`. When `API_KEY` is unset
(local dev) the check is skipped. Swapping in Firebase ID-token verification is
a drop-in replacement dependency here.
"""

from __future__ import annotations

from fastapi import Header, HTTPException, status

from app.config import get_settings


async def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    settings = get_settings()
    if not settings.api_key:
        return  # auth disabled — dev mode
    if x_api_key != settings.api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key.",
        )
