"""Email delivery. Two modes, picked automatically from what's configured:

* ``smtp``     — Gmail SMTP with an App Password. Easiest to set up.
* ``gmail_api``— Gmail API with an OAuth refresh token. Use where outbound SMTP
                 is blocked (some PaaS hosts).
* ``dry_run``  — logs instead of sending, so the whole flow works with zero
                 credentials.

Both real modes are blocking, so callers run ``send`` via ``asyncio.to_thread``
to keep the event loop free.
"""

from __future__ import annotations

import base64
import logging
import smtplib
from email.message import EmailMessage
from email.utils import formataddr
from functools import lru_cache

from app.config import Settings

logger = logging.getLogger("mailer")

GMAIL_SCOPES = ["https://www.googleapis.com/auth/gmail.send"]
_TOKEN_URI = "https://oauth2.googleapis.com/token"

# A Google App Password is always 16 characters (shown as 4 groups of 4).
_APP_PASSWORD_LEN = 16


class MailerNotConfigured(RuntimeError):
    """Raised when a real send is attempted without usable credentials."""


def provider(settings: Settings) -> str:
    """Which delivery mode a send would use right now."""
    if settings.dry_run:
        return "dry_run"
    if not settings.email_user:
        return "unconfigured"
    if settings.gmail_client_id and settings.gmail_client_secret and settings.gmail_refresh_token:
        return "gmail_api"
    if settings.email_app_password:
        return "smtp"
    return "unconfigured"


def config_hint(settings: Settings) -> str | None:
    """Human-readable reason sending would fail, or None when it's ready."""
    mode = provider(settings)

    if mode == "smtp" and len(settings.email_app_password.replace(" ", "")) != _APP_PASSWORD_LEN:
        # Gmail refuses a normal account password over SMTP (534 5.7.9), so
        # catch the wrong-value case before we try to deliver anything.
        return (
            "EMAIL_APP_PASSWORD must be a 16-character Google App Password, not your "
            "normal account password. Enable 2-Step Verification, then create one at "
            "https://myaccount.google.com/apppasswords"
        )

    if mode != "unconfigured":
        return None

    if not settings.email_user:
        return "Set EMAIL_USER (the Gmail address that sends), then either EMAIL_APP_PASSWORD or the GMAIL_* OAuth values."
    return (
        "Set EMAIL_APP_PASSWORD (Gmail App Password) or GMAIL_CLIENT_ID/"
        "GMAIL_CLIENT_SECRET/GMAIL_REFRESH_TOKEN — or keep DRY_RUN=true."
    )


def _build_message(
    settings: Settings,
    *,
    to_email: str,
    to_name: str | None,
    subject: str,
    body: str,
    is_html: bool,
) -> EmailMessage:
    message = EmailMessage()
    message["To"] = formataddr((to_name, to_email)) if to_name else to_email
    message["From"] = formataddr((settings.from_name or None, settings.email_user))
    message["Subject"] = subject
    if is_html:
        # Plain-text alternative keeps the mail out of spam filters that dislike
        # HTML-only bodies; the HTML part is what recipients normally see.
        message.set_content("This email requires an HTML-capable mail client.")
        message.add_alternative(body, subtype="html")
    else:
        message.set_content(body)
    return message


def _send_smtp(settings: Settings, message: EmailMessage) -> None:
    # Google displays App Passwords in groups of four; the spaces aren't part of it.
    password = settings.email_app_password.replace(" ", "")
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=30) as smtp:
        smtp.starttls()
        try:
            smtp.login(settings.email_user, password)
        except smtplib.SMTPAuthenticationError as exc:
            raise MailerNotConfigured(
                f"Gmail rejected the login for {settings.email_user} ({exc.smtp_code}). "
                "EMAIL_APP_PASSWORD must be a 16-character App Password from "
                "https://myaccount.google.com/apppasswords (2-Step Verification required), "
                "not your normal account password."
            ) from exc
        smtp.send_message(message)


@lru_cache
def _gmail_service(client_id: str, client_secret: str, refresh_token: str):
    """Build (and cache) a Gmail service so we don't refresh a token per send."""
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build

    creds = Credentials(
        None,
        refresh_token=refresh_token,
        client_id=client_id,
        client_secret=client_secret,
        token_uri=_TOKEN_URI,
        scopes=GMAIL_SCOPES,
    )
    return build("gmail", "v1", credentials=creds, cache_discovery=False)


def _send_gmail_api(settings: Settings, message: EmailMessage) -> None:
    raw = base64.urlsafe_b64encode(message.as_bytes()).decode()
    service = _gmail_service(
        settings.gmail_client_id,
        settings.gmail_client_secret,
        settings.gmail_refresh_token,
    )
    service.users().messages().send(userId="me", body={"raw": raw}).execute()


def send(
    settings: Settings,
    *,
    to_email: str,
    to_name: str | None = None,
    subject: str,
    body: str,
    is_html: bool = True,
) -> None:
    """Send one email. Blocking; raises on failure so the caller can report it."""
    mode = provider(settings)

    if mode == "dry_run":
        logger.info(
            "[DRY_RUN] would send to %s | subject=%r | %d chars", to_email, subject, len(body)
        )
        return

    if mode == "unconfigured":
        raise MailerNotConfigured(config_hint(settings) or "Mailer is not configured.")

    message = _build_message(
        settings,
        to_email=to_email,
        to_name=to_name,
        subject=subject,
        body=body,
        is_html=is_html,
    )
    if mode == "gmail_api":
        _send_gmail_api(settings, message)
    else:
        _send_smtp(settings, message)
    logger.info("sent to %s via %s", to_email, mode)
