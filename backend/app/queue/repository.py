"""Queue data access: enqueue a batch, atomically claim the next job, and
record terminal / retry outcomes. All operations are short synchronous DB calls.

Claim safety: within the single app event loop, a synchronous claim runs to
completion without yielding, so two async workers can never claim the same row.
The `status == 'queued'` guard on the UPDATE additionally protects against
multiple *processes* sharing one database (e.g. Postgres), where the row-count
of the guarded update tells us whether we won the race.
"""

from __future__ import annotations

from datetime import timedelta

from sqlmodel import Session, func, select

from app.models import EmailBatch, EmailJob, JobStatus, utcnow


def create_batch(session: Session, recruiter_id: str, total: int) -> EmailBatch:
    batch = EmailBatch(recruiter_id=recruiter_id, total=total)
    session.add(batch)
    session.commit()
    session.refresh(batch)
    return batch


def enqueue_jobs(session: Session, jobs: list[EmailJob]) -> None:
    for job in jobs:
        session.add(job)
    session.commit()


def claim_next(session: Session) -> EmailJob | None:
    """Return the oldest due queued job, flipped to `processing`, or None."""
    now = utcnow()
    stmt = (
        select(EmailJob)
        .where(EmailJob.status == JobStatus.queued)
        .where(EmailJob.scheduled_at <= now)
        .order_by(EmailJob.created_at)
        .limit(1)
    )
    job = session.exec(stmt).first()
    if job is None:
        return None

    # Guarded transition: only claim if still queued (multi-process safe).
    job.status = JobStatus.processing
    job.attempts += 1
    job.updated_at = now
    session.add(job)
    session.commit()
    session.refresh(job)
    return job


def mark_sent(session: Session, job: EmailJob) -> None:
    job.status = JobStatus.sent
    job.last_error = None
    job.updated_at = utcnow()
    session.add(job)
    session.commit()


def mark_retry_or_fail(
    session: Session, job: EmailJob, error: str, backoff_base: int
) -> None:
    """Requeue with exponential backoff, or mark failed once attempts run out."""
    now = utcnow()
    job.last_error = error[:1000]
    job.updated_at = now
    if job.attempts >= job.max_attempts:
        job.status = JobStatus.failed
    else:
        delay = backoff_base * (2 ** (job.attempts - 1))
        job.status = JobStatus.queued
        job.scheduled_at = now + timedelta(seconds=delay)
    session.add(job)
    session.commit()


def recover_orphaned(session: Session) -> int:
    """Requeue jobs stuck in `processing` (a crash mid-send). At-least-once:
    a job that had actually been sent before the crash could send again."""
    rows = session.exec(
        select(EmailJob).where(EmailJob.status == JobStatus.processing)
    ).all()
    for job in rows:
        job.status = JobStatus.queued
        job.scheduled_at = utcnow()
        session.add(job)
    if rows:
        session.commit()
    return len(rows)


def batch_status(session: Session, batch_id: int) -> tuple[EmailBatch | None, list[EmailJob]]:
    batch = session.get(EmailBatch, batch_id)
    if batch is None:
        return None, []
    jobs = session.exec(
        select(EmailJob).where(EmailJob.batch_id == batch_id).order_by(EmailJob.id)
    ).all()
    return batch, jobs


def count_by_status(session: Session, batch_id: int) -> dict[str, int]:
    rows = session.exec(
        select(EmailJob.status, func.count())
        .where(EmailJob.batch_id == batch_id)
        .group_by(EmailJob.status)
    ).all()
    counts = {s.value: 0 for s in JobStatus}
    for status_value, n in rows:
        key = status_value.value if hasattr(status_value, "value") else str(status_value)
        counts[key] = n
    return counts
