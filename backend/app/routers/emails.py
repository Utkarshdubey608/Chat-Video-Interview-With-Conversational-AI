"""Email endpoints.

`POST /api/emails/send` renders one email per selected candidate, enqueues them
as jobs, and returns 202 immediately — the API never blocks on delivery. Workers
drain the queue in the background. Callers can poll batch status.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlmodel import Session

from app.db import get_session
from app.models import EmailJob, JobStatus
from app.queue import repository as repo
from app.schemas import (
    BatchStatus,
    EnqueueResponse,
    JobRead,
    Recipient,
    SendEmailRequest,
)
from app.security import require_api_key
from app.templating import DEFAULT_BODY, DEFAULT_SUBJECT, render

router = APIRouter(
    prefix="/api/emails",
    tags=["emails"],
    dependencies=[Depends(require_api_key)],
)


def _resolve_template(req: SendEmailRequest, session: Session) -> tuple[str, str]:
    """Pick subject/body: inline > saved template > built-in default."""
    from app.models import EmailTemplate

    subject, body = req.subject, req.body
    if (subject is None or body is None) and req.template_id is not None:
        tpl = session.get(EmailTemplate, req.template_id)
        if tpl is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Template not found.")
        if tpl.recruiter_id != req.recruiter_id:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN, "Template belongs to another recruiter."
            )
        subject = subject if subject is not None else tpl.subject
        body = body if body is not None else tpl.body
    return subject or DEFAULT_SUBJECT, body or DEFAULT_BODY


def _context_for(req: SendEmailRequest, r: Recipient) -> dict[str, str]:
    name = r.name or r.email.split("@")[0]
    # shared context < per-recipient context < the candidate's own identity.
    return {
        **req.shared_context,
        **r.context,
        "candidate_name": name,
        "candidate_email": r.email,
    }


@router.post(
    "/send",
    response_model=EnqueueResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def send_invites(
    req: SendEmailRequest,
    request: Request,
    session: Session = Depends(get_session),
) -> EnqueueResponse:
    # Settings + queue manager live on app.state (wired in main.py lifespan).
    app_settings = request.app.state.settings
    subject_tpl, body_tpl = _resolve_template(req, session)

    batch = repo.create_batch(session, req.recruiter_id, len(req.recipients))

    jobs: list[EmailJob] = []
    for r in req.recipients:
        ctx = _context_for(req, r)
        jobs.append(
            EmailJob(
                batch_id=batch.id,
                recruiter_id=req.recruiter_id,
                to_email=str(r.email),
                to_name=r.name,
                subject=render(subject_tpl, ctx),
                body=render(body_tpl, ctx),
                is_html=req.is_html,
                status=JobStatus.queued,
                max_attempts=app_settings.job_max_attempts,
            )
        )
    repo.enqueue_jobs(session, jobs)

    # Nudge idle workers so delivery starts immediately.
    request.app.state.queue.notify()

    return EnqueueResponse(batch_id=batch.id, queued=len(jobs))


@router.get("/batches/{batch_id}", response_model=BatchStatus)
async def get_batch_status(
    batch_id: int,
    session: Session = Depends(get_session),
) -> BatchStatus:
    batch, jobs = repo.batch_status(session, batch_id)
    if batch is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Batch not found.")
    counts = repo.count_by_status(session, batch_id)
    return BatchStatus(
        batch_id=batch.id,
        recruiter_id=batch.recruiter_id,
        total=batch.total,
        queued=counts.get(JobStatus.queued.value, 0),
        processing=counts.get(JobStatus.processing.value, 0),
        sent=counts.get(JobStatus.sent.value, 0),
        failed=counts.get(JobStatus.failed.value, 0),
        jobs=[
            JobRead(
                id=j.id,
                to_email=j.to_email,
                status=j.status,
                attempts=j.attempts,
                last_error=j.last_error,
            )
            for j in jobs
        ],
    )
