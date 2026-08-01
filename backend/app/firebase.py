"""Firestore access — the only storage this service uses.

Saved templates live in the same Firebase project as the mobile app
(`talbotiq-9cc4e` by default). The Admin SDK is initialised lazily so the API
starts, serves built-in templates, and sends mail even with no credentials
present; only the saved-template endpoints need Firestore.
"""

from __future__ import annotations

import json
import logging
import os
import threading

from app.config import Settings

logger = logging.getLogger("firebase")

_lock = threading.Lock()
_client = None  # cached google.cloud.firestore.Client


class FirestoreUnavailable(RuntimeError):
    """Raised when Firestore is needed but isn't configured/reachable."""


def _credentials(settings: Settings):
    """Service-account credentials from a file, inline JSON, or ADC.

    With FIRESTORE_EMULATOR_HOST set (`firebase emulators:start --only firestore`)
    no real credentials exist, so anonymous ones are used.
    """
    from firebase_admin import credentials

    if os.environ.get("FIRESTORE_EMULATOR_HOST"):
        from google.auth.credentials import AnonymousCredentials

        class _Anonymous(credentials.Base):
            def get_credential(self):
                return AnonymousCredentials()

        logger.info("using the Firestore emulator at %s", os.environ["FIRESTORE_EMULATOR_HOST"])
        return _Anonymous()

    if settings.firebase_credentials_json.strip():
        return credentials.Certificate(json.loads(settings.firebase_credentials_json))
    if settings.firebase_credentials_file.strip():
        return credentials.Certificate(settings.firebase_credentials_file)
    return credentials.ApplicationDefault()


def get_db(settings: Settings):
    """Return a Firestore client, or raise FirestoreUnavailable with a hint."""
    global _client
    if _client is not None:
        return _client

    with _lock:
        if _client is not None:
            return _client
        try:
            import firebase_admin
            from firebase_admin import firestore
        except ImportError as exc:  # pragma: no cover - dependency is in requirements
            raise FirestoreUnavailable(
                "firebase-admin is not installed. Run: pip install -r requirements.txt"
            ) from exc

        try:
            if not firebase_admin._apps:
                firebase_admin.initialize_app(
                    _credentials(settings),
                    {"projectId": settings.firebase_project_id},
                )
            _client = firestore.client()
        except Exception as exc:  # noqa: BLE001 - surfaced to the caller as 503
            raise FirestoreUnavailable(
                "Firestore is not configured: "
                f"{exc}. Set FIREBASE_CREDENTIALS_FILE (service-account JSON) or "
                "FIREBASE_CREDENTIALS_JSON. Built-in templates and sending work without it."
            ) from exc

    return _client


def is_configured(settings: Settings) -> bool:
    """Cheap check used by /health — never raises."""
    try:
        get_db(settings)
        return True
    except FirestoreUnavailable:
        return False
