"""Gmail API delivery using an OAuth refresh token.

Based on the reference concept: build OAuth credentials from a stored refresh
token, construct the Gmail service, and send a base64url-encoded MIME message
via users().messages().send(). The googleapiclient is synchronous, so callers
run send() in a worker thread (see the queue worker) to keep the event loop free.

Honours DRY_RUN: logs instead of sending, so the queue flow can be exercised
with no Gmail credentials at all.
"""

from __future__ import annotations

import base64
import logging
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from functools import lru_cache

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

from app.config import Settings

logger = logging.getLogger("gmail")

GMAIL_SCOPES = ["https://www.googleapis.com/auth/gmail.send"]
_TOKEN_URI = "https://oauth2.googleapis.com/token"


class GmailNotConfigured(RuntimeError):
    """Raised when a real send is attempted without OAuth credentials."""


def _missing(settings: Settings) -> list[str]:
    required = {
        "EMAIL_USER": settings.email_user,
        "GMAIL_CLIENT_ID": settings.gmail_client_id,
        "GMAIL_CLIENT_SECRET": settings.gmail_client_secret,
        "GMAIL_REFRESH_TOKEN": settings.gmail_refresh_token,
    }
    return [name for name, value in required.items() if not value]


@lru_cache
def _service(client_id: str, client_secret: str, refresh_token: str):
    """Build (and cache) a Gmail service for the given credentials.

    Cached so we don't rebuild the client / refresh a token on every send.
    """
    creds = Credentials(
        None,
        refresh_token=refresh_token,
        client_id=client_id,
        client_secret=client_secret,
        token_uri=_TOKEN_URI,
        scopes=GMAIL_SCOPES,
    )
    return build("gmail", "v1", credentials=creds, cache_discovery=False)


def send(
    settings: Settings,
    *,
    to_email: str,
    to_name: str | None,
    subject: str,
    body: str,
    is_html: bool = True,
) -> None:
    """Send one email. Blocking — call via asyncio.to_thread from async code.
    Raises on failure so the caller can record per-job status."""

    if settings.dry_run:
        logger.info(
            "[DRY_RUN] would send to %s | subject=%r | %d chars",
            to_email,
            subject,
            len(body),
        )
        return

    missing = _missing(settings)
    if missing:
        raise GmailNotConfigured(
            "Gmail is not configured; missing: " + ", ".join(missing)
        )

    message = MIMEMultipart("alternative")
    message["To"] = f"{to_name} <{to_email}>" if to_name else to_email
    message["From"] = (
        f"{settings.app_name} <{settings.email_user}>"
        if settings.app_name
        else settings.email_user
    )
    message["Subject"] = subject
    message.attach(MIMEText(body, "html" if is_html else "plain", "utf-8"))

    raw = base64.urlsafe_b64encode(message.as_bytes()).decode()
    service = _service(
        settings.gmail_client_id,
        settings.gmail_client_secret,
        settings.gmail_refresh_token,
    )
    service.users().messages().send(userId="me", body={"raw": raw}).execute()
