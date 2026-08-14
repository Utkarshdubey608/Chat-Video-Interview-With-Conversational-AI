"""Who the caller is — a port of `server/services/users.ts` and `getUserRole`.

The role is NOT decided here. It lives on Firestore `users/{uid}.role`, written by
the user at sign-up and read by three things that must agree: the web client, the
Flutter app (`auth_service.dart`), and this server. Reading the same document is
what keeps them in lock-step.

A missing or unreadable document resolves to `candidate` — least privilege, and
the same default the clients' auth gates use.

⚠️ Because that document is client-writable, a user can self-select the
`recruiter` role at sign-up. That is the agreed interop model with the Flutter
app, not an oversight. The `admin` overlay below is the one thing that stays
server-authoritative and can never be set from a client. To harden the role
itself, move role assignment server-side and tighten `firestore.rules`.

The JSON store's `users` map is deliberately NOT recreated: it only mirrored this
same Firestore document, and a mirror of a shared fact is a second source of
truth for it.
"""

from __future__ import annotations

import asyncio
import logging

from app.config import Settings
from app.firebase import get_db
from app.security import AuthedUser

logger = logging.getLogger("web.users")

USERS_COLLECTION = "users"

RECRUITER = "recruiter"
CANDIDATE = "candidate"


async def get_role(settings: Settings, uid: str) -> str:
    """The role recorded on `users/{uid}`, defaulting to `candidate`.

    Never raises: an unreachable Firestore must not turn every authenticated
    request into a 500 when the safe answer — least privilege — is available.
    """
    if not uid:
        return CANDIDATE

    def _read() -> str:
        snapshot = get_db(settings).collection(USERS_COLLECTION).document(uid).get()
        if not snapshot.exists:
            return CANDIDATE
        value = (snapshot.to_dict() or {}).get("role")
        return RECRUITER if value == RECRUITER else CANDIDATE

    try:
        return await asyncio.to_thread(_read)
    except Exception as exc:  # noqa: BLE001 - degrade to least privilege, never 500
        logger.warning("could not read role for %s: %s", uid, type(exc).__name__)
        return CANDIDATE


async def get_display_name(settings: Settings, uid: str) -> str | None:
    """The `name` on `users/{uid}`, when the client recorded one.

    Used for the recruiter's display name on an invite. Best-effort by design —
    an invite must not fail because a profile field is missing.
    """
    if not uid:
        return None

    def _read() -> str | None:
        snapshot = get_db(settings).collection(USERS_COLLECTION).document(uid).get()
        if not snapshot.exists:
            return None
        data = snapshot.to_dict() or {}
        value = data.get("name") or data.get("displayName")
        return str(value).strip() or None if value else None

    try:
        return await asyncio.to_thread(_read)
    except Exception as exc:  # noqa: BLE001 - a display name is never worth a 500
        logger.warning("could not read name for %s: %s", uid, type(exc).__name__)
        return None


def admin_emails(settings: Settings) -> set[str]:
    """The server-side admin allowlist, lowercased. Empty disables the overlay."""
    raw = settings.admin_emails or ""
    return {
        part.strip().lower()
        for part in raw.replace("\n", ",").replace(" ", ",").split(",")
        if part.strip()
    }


def is_admin(settings: Settings, *, email: str | None, role: str) -> bool:
    """Is this an admin — a recruiter on the ADMIN_EMAILS allowlist?

    Derived from the token's VERIFIED email and a server-side env var, so a client
    cannot claim it. Requires the recruiter role: the overlay grants a recruiter
    wider visibility, it does not promote a candidate.

    ROLE-GATING: nothing currently ACTS on this — the Express server used it to
    widen a recruiter's session list, and that behaviour is parked with role
    gating. It is still reported by `/auth/me` so the web client's display is
    unchanged.
    """
    if role != RECRUITER:
        return False
    normalised = (email or "").strip().lower()
    return bool(normalised) and normalised in admin_emails(settings)


def email_verified(user: AuthedUser) -> bool:
    """Whether Firebase has verified this address.

    Read from the token's claims, not from any document — a client-writable field
    saying "verified" would mean nothing.
    """
    return user.claims.get("email_verified") is True
