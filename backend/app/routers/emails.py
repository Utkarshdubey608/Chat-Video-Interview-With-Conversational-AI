"""`POST /api/emails/send` — render the chosen template once per candidate and
deliver it, returning a per-recipient result.

Delivery runs in threads (a few in parallel) so the event loop stays free;
there's no queue and no database in the path.
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app import mailer, templates_store
from app.config import Settings
from app.firebase import FirestoreUnavailable
from app.schemas import Recipient, SendEmailRequest, SendResponse, SendResult
from app.security import require_api_key
from app.templating import render

router = APIRouter(
    prefix="/api/emails",
    tags=["emails"],
    dependencies=[Depends(require_api_key)],
)


def _resolve_template(settings: Settings, req: SendEmailRequest) -> dict:
    """The chosen template, or the default one when no id was given.
    Inline subject/body/is_html override whatever the template says."""
    if req.template_id:
        try:
            template = templates_store.get(
                settings, req.template_id, owner_email=req.owner_email
            )
        except templates_store.TemplateNotFound as exc:
            raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
        except FirestoreUnavailable as exc:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc)) from exc
    else:
        template = templates_store.default_template()

    return {
        **template,
        "subject": req.subject if req.subject is not None else template["subject"],
        "body": req.body if req.body is not None else template["body"],
        "is_html": req.is_html if req.is_html is not None else template["is_html"],
    }


def _context_for(req: SendEmailRequest, r: Recipient) -> dict[str, str]:
    name = r.name or str(r.email).split("@")[0]
    # shared context < per-recipient context < the candidate's own identity.
    return {
        **req.shared_context,
        **r.context,
        "candidate_name": name,
        "candidate_email": str(r.email),
    }


@router.post("/send", response_model=SendResponse)
async def send_invites(req: SendEmailRequest, request: Request) -> SendResponse:
    settings: Settings = request.app.state.settings
    template = _resolve_template(settings, req)

    hint = mailer.config_hint(settings)
    if hint:
        # Fail loudly up front rather than reporting every recipient as failed.
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, hint)

    limit = asyncio.Semaphore(max(1, settings.send_concurrency))

    async def deliver(r: Recipient) -> SendResult:
        ctx = _context_for(req, r)
        async with limit:
            try:
                await asyncio.to_thread(
                    mailer.send,
                    settings,
                    to_email=str(r.email),
                    to_name=r.name,
                    subject=render(template["subject"], ctx),
                    body=render(template["body"], ctx),
                    is_html=template["is_html"],
                )
            except Exception as exc:  # noqa: BLE001 - one bad address must not sink the batch
                return SendResult(email=r.email, status="failed", error=str(exc)[:500])
        return SendResult(email=r.email, status="sent")

    results = await asyncio.gather(*(deliver(r) for r in req.recipients))
    sent = sum(1 for r in results if r.status == "sent")

    return SendResponse(
        total=len(results),
        sent=sent,
        failed=len(results) - sent,
        template_id=template["id"],
        provider=mailer.provider(settings),
        subject_preview=render(template["subject"], _context_for(req, req.recipients[0])),
        results=list(results),
    )
