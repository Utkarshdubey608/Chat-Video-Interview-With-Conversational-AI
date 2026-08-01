"""Templates: the built-ins that ship in code + custom ones saved in Firestore.

Documents in the `email_templates` collection use camelCase field names to match
the mobile app's Firestore conventions:

    { name, description, subject, body, isHtml, ownerEmail, recruiterId, createdAt }

`ownerEmail` (lowercased) is what scopes a template to the recruiter who created
it: they only ever see the built-ins plus their own.
"""

from __future__ import annotations

from datetime import datetime, timezone

from app.config import Settings
from app.firebase import get_db
from app.templating import BUILTIN_BY_ID, BUILTIN_TEMPLATES, DEFAULT_TEMPLATE_ID


class TemplateNotFound(LookupError):
    pass


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _collection(settings: Settings):
    return get_db(settings).collection(settings.templates_collection)


def normalize_email(email: str | None) -> str:
    return (email or "").strip().lower()


def _to_dict(doc) -> dict:
    data = doc.to_dict() or {}
    return {
        "id": doc.id,
        "name": data.get("name", "Untitled template"),
        "description": data.get("description"),
        "subject": data.get("subject", ""),
        "body": data.get("body", ""),
        "is_html": bool(data.get("isHtml", True)),
        "owner_email": data.get("ownerEmail"),
        "recruiter_id": data.get("recruiterId"),
        "source": "custom",
        "is_default": False,
    }


def builtin_list() -> list[dict]:
    """The ready-made templates. Always available, no Firebase needed."""
    return [
        {
            **t,
            "owner_email": None,
            "recruiter_id": None,
            "source": "builtin",
            "is_default": t["id"] == DEFAULT_TEMPLATE_ID,
        }
        for t in BUILTIN_TEMPLATES
    ]


def list_all(settings: Settings, owner_email: str | None = None) -> tuple[list[dict], str | None]:
    """Templates this recruiter can pick: built-ins first, then the custom ones
    they created (newest first). Without an `owner_email` only the built-ins are
    returned — one recruiter never sees another's templates.

    Returns (templates, warning); `warning` is set when Firestore is unreachable
    so the built-ins stay usable.
    """
    rows = builtin_list()
    owner = normalize_email(owner_email)
    if not owner:
        return rows, None

    try:
        docs = list(_collection(settings).where("ownerEmail", "==", owner).stream())
    except Exception as exc:  # noqa: BLE001 - degrade to built-ins with a note
        return rows, f"Your saved templates are unavailable: {exc}"

    # Sorted here rather than in the query so no Firestore composite index is
    # needed for the (ownerEmail, createdAt) pair.
    saved = [(_to_dict(d), (d.to_dict() or {}).get("createdAt")) for d in docs]
    saved.sort(key=lambda r: -_epoch(r[1]))
    return rows + [row for row, _ in saved], None


def _epoch(value) -> float:
    """Sort key for a Firestore timestamp / datetime / missing value."""
    if isinstance(value, datetime):
        stamped = value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        return stamped.timestamp()
    return 0.0


def get(settings: Settings, template_id: str, *, owner_email: str | None = None) -> dict:
    """Resolve a built-in ("builtin:…") or a saved Firestore template id.

    When `owner_email` is given, someone else's custom template reads as
    not-found, so a guessed id can't be used to send with another recruiter's
    template.
    """
    if template_id.startswith("builtin:"):
        template = BUILTIN_BY_ID.get(template_id)
        if template is None:
            raise TemplateNotFound(f"No built-in template '{template_id}'.")
        return {
            **template,
            "owner_email": None,
            "recruiter_id": None,
            "source": "builtin",
            "is_default": template_id == DEFAULT_TEMPLATE_ID,
        }

    doc = _collection(settings).document(template_id).get()
    if not doc.exists:
        raise TemplateNotFound(f"No template '{template_id}'.")
    row = _to_dict(doc)

    owner = normalize_email(owner_email)
    if owner and row["owner_email"] and row["owner_email"] != owner:
        raise TemplateNotFound(f"No template '{template_id}'.")
    return row


def default_template() -> dict:
    """Used when a send request names no template."""
    return {
        **BUILTIN_BY_ID[DEFAULT_TEMPLATE_ID],
        "owner_email": None,
        "recruiter_id": None,
        "source": "builtin",
        "is_default": True,
    }


def create(settings: Settings, payload: dict) -> dict:
    """Save a custom template in Firestore and return it with its new id."""
    doc = {
        "name": payload.get("name") or "Untitled template",
        "description": payload.get("description"),
        "subject": payload.get("subject", ""),
        "body": payload.get("body", ""),
        "isHtml": bool(payload.get("is_html", True)),
        "ownerEmail": normalize_email(payload.get("owner_email")),
        "recruiterId": payload.get("recruiter_id"),
        "createdAt": utcnow(),
    }
    ref = _collection(settings).document()
    ref.set(doc)
    return get(settings, ref.id)
