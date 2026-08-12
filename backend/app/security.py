"""Authentication.

Two schemes, for two different kinds of caller:

``require_api_key`` — the legacy shared secret (``X-API-Key``) guarding the
mailer routes. Kept as-is so nothing that works today breaks.

``require_firebase_user`` — a verified Firebase ID token, required by the AI
proxy and token-minting routes. Those routes spend real money and can mint
credentials, so they need to know *which user* is calling, not merely that the
caller holds a secret. A shared secret compiled into the app bundle would be an
unrotatable shipped credential: anyone who extracted it could burn the org's
Gemini and Tavus quota. An ID token is per-user, short-lived and revocable.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from fastapi import Depends, Header, HTTPException, Request, status

from app.config import Settings, get_settings
from app.firebase import FirestoreUnavailable, ensure_app

logger = logging.getLogger("security")


async def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """Shared-secret auth for the mailer routes.

    When `API_KEY` is unset the check is skipped (local dev).
    """
    settings = get_settings()
    if not settings.api_key:
        return  # auth disabled — dev mode
    if x_api_key != settings.api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key.",
        )


@dataclass(frozen=True)
class AuthedUser:
    """The verified caller. `claims` is the raw decoded token."""

    uid: str
    email: str | None
    claims: dict

    @property
    def role(self) -> str | None:
        """Custom-claim role ('recruiter' | 'candidate'), when the project sets one.

        Absent for most users — role lives in Firestore today — so callers must
        treat `None` as "unknown" and fall back to a document check rather than
        denying outright.
        """
        value = self.claims.get("role")
        return value if isinstance(value, str) else None


def _settings(request: Request) -> Settings:
    """Settings off app.state, falling back to the cached instance (tests)."""
    return getattr(request.app.state, "settings", None) or get_settings()


async def require_firebase_user(
    request: Request,
    authorization: str | None = Header(default=None),
) -> AuthedUser:
    """Verify `Authorization: Bearer <Firebase ID token>` and return the caller."""
    settings = _settings(request)

    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=(
                "Missing bearer token. Send a Firebase ID token as "
                "'Authorization: Bearer <token>'."
            ),
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        ensure_app(settings)
    except FirestoreUnavailable as exc:
        # No credentials on the server: a configuration fault, not the caller's.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Authentication is unavailable: {exc}",
        ) from exc

    from firebase_admin import auth as firebase_auth

    try:
        # check_revoked catches sign-out and disabled accounts at the cost of a
        # lookup — worth it on routes that can mint credentials.
        claims = firebase_auth.verify_id_token(token.strip(), check_revoked=True)
    except Exception as exc:  # noqa: BLE001 - every failure here is an auth failure
        # Never log the token itself.
        logger.info("ID token rejected: %s", type(exc).__name__)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired sign-in. Sign in again and retry.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    uid = claims.get("uid") or claims.get("sub") or ""
    if not uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token carries no uid.",
        )

    return AuthedUser(uid=uid, email=claims.get("email"), claims=claims)


# Convenience so routers read as `user: AuthedUser = CurrentUser`.
CurrentUser = Depends(require_firebase_user)
