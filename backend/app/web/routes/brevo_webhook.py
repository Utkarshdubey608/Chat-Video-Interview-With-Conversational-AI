"""Brevo delivery webhook — ports `server/routes/brevoWebhook.ts`.

**PUBLIC**, because Brevo sends no bearer token. A shared secret is the only thing
authenticating it: `BREVO_WEBHOOK_SECRET` must match `?token=` or the
`x-webhook-token` header.

It **fails closed** — with no secret configured every request is rejected. An open
endpoint here would let anyone rewrite an invite's delivery status, which is what a
recruiter uses to decide whether a candidate ever received their interview.

Correlation is by the `X-Mailin-custom` header each invite carries, which Brevo echoes
back. Failing that it falls back to the most recent invite for the recipient's address
— ambiguous for a candidate invited to several roles, which is exactly why the header
exists.

Every response is 200, including the rejections-by-policy and the events we ignore: a
non-2xx makes Brevo retry, and a retry storm over an event we deliberately discard is
worse than the event being lost. The 401 is the one exception — that is a
misconfiguration worth surfacing.

Webhooks need a publicly reachable URL, so on localhost the events never arrive.
Send-time `accepted` / `failed` and the retry route still work; `delivered`, `opened`
and `bounced` need a tunnel or a deployed environment.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Body, Header, Query, Request
from fastapi.responses import JSONResponse

from app.web.deps import settings_of
from app.web.services.interview_invite import interviews

logger = logging.getLogger("web.brevo_webhook")

# Mounted BEFORE /invites so this more specific path wins, and because it must NOT
# inherit that router's authentication.
router = APIRouter(prefix="/invites/brevo-webhook", tags=["web:invites"])

# Brevo's event names → our invite status. Several vendor names collapse onto one of
# ours: a hard and a soft bounce are both "the mail did not arrive" to a recruiter.
_EVENT_STATUS = {
    "delivered": "delivered",
    "hardbounce": "bounced",
    "hard_bounce": "bounced",
    "softbounce": "bounced",
    "soft_bounce": "bounced",
    "spam": "spam",
    "blocked": "failed",
    "invalid": "failed",
    "error": "failed",
    "deferred": "failed",
    "opened": "opened",
    "uniqueopened": "opened",
    "unique_opened": "opened",
    "open": "opened",
    "click": "clicked",
    "clicked": "clicked",
}


def map_event(event: object) -> str | None:
    """Our status for a Brevo event, or None to ignore it.

    `request`, `sent` and `unsubscribed` deliberately map to None: they describe
    Brevo's own queue rather than whether the candidate got the mail, and letting them
    overwrite a `delivered` would lose information.
    """
    return _EVENT_STATUS.get(str(event or "").strip().lower())


def interview_id_from(payload: dict) -> str | None:
    """The interview id out of the echoed `X-Mailin-custom` value.

    Brevo returns it under several names depending on the event type, and sometimes as
    an already-parsed object rather than a JSON string — hence both branches.
    """
    raw = (
        payload.get("X-Mailin-custom")
        or payload.get("x-mailin-custom")
        or payload.get("mailincustom")
        or payload.get("tag")
    )
    if not raw:
        return None

    try:
        parsed = json.loads(raw) if isinstance(raw, str) else raw
    except (TypeError, ValueError):
        return None

    if isinstance(parsed, dict) and parsed.get("interviewId"):
        return str(parsed["interviewId"])
    return None


@router.post("", summary="Brevo delivery events (public, shared-secret)")
async def receive(
    request: Request,
    payload: dict = Body(default={}),
    token: str = Query(default=""),
    x_webhook_token: str | None = Header(default=None),
) -> JSONResponse:
    settings = settings_of(request)
    secret = settings.brevo_webhook_secret.strip()
    provided = (token or x_webhook_token or "").strip()

    # Fails closed: no configured secret means no accepted requests.
    if not secret or provided != secret:
        logger.warning("brevo webhook rejected: bad or missing token")
        return JSONResponse(
            {"ok": False, "error": "Invalid webhook token"}, status_code=401
        )

    status = map_event(payload.get("event"))
    if not status:
        # Acknowledged, not an error. Brevo retries anything non-2xx.
        return JSONResponse({"ok": True, "ignored": True})

    try:
        await _apply(settings, payload, status)
    except Exception as exc:  # noqa: BLE001 - still acknowledge; the event is not critical
        logger.error("brevo webhook update failed: %s", exc)

    return JSONResponse({"ok": True})


async def _apply(settings, payload: dict, status: str) -> None:
    """Write the status onto the matching interview. Best-effort."""
    import asyncio

    collection = interviews(settings)
    interview_id = interview_id_from(payload)
    email = str(payload.get("email") or "").strip().lower()

    def _write() -> None:
        reference = None

        if interview_id:
            candidate = collection.document(interview_id)
            if candidate.get().exists:
                reference = candidate

        if reference is None and email:
            # Fallback: the most recent invite for this address. Ambiguous when the
            # candidate was invited to several roles, which is why the header is
            # preferred.
            found = (
                collection.where("candidateEmailLower", "==", email)
                .order_by("createdAt", direction="DESCENDING")
                .limit(1)
                .get()
            )
            if found:
                reference = found[0].reference

        if reference is None:
            logger.info("brevo webhook: no interview matched (event=%s)", status)
            return

        # Dotted paths, so a delivery event cannot clobber the messageId, attempts or
        # error already recorded at send time.
        reference.update(
            {
                "invite.status": status,
                "invite.lastEventAt": datetime.now(timezone.utc).isoformat(),
            }
        )

    await asyncio.to_thread(_write)
