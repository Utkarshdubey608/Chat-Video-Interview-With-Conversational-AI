"""Persisted models: recruiter email templates + the email job queue."""

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum

from sqlmodel import Field, SQLModel


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class JobStatus(str, Enum):
    queued = "queued"
    processing = "processing"
    sent = "sent"
    failed = "failed"


class EmailTemplate(SQLModel, table=True):
    """A reusable email template owned by one recruiter.

    `subject` and `body` may contain `{{ variable }}` placeholders filled
    per-recipient at send time (see app.templating). At most one template per
    recruiter is flagged `is_default` (pre-selected in the UI).
    """

    __tablename__ = "email_templates"

    id: int | None = Field(default=None, primary_key=True)
    recruiter_id: str = Field(index=True, description="Firebase uid of the owner")
    name: str = Field(default="Untitled template")
    subject: str = Field(default="")
    body: str = Field(default="")
    is_default: bool = Field(default=False)
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)


class EmailBatch(SQLModel, table=True):
    """One `POST /api/emails/send` request — groups the jobs it enqueued."""

    __tablename__ = "email_batches"

    id: int | None = Field(default=None, primary_key=True)
    recruiter_id: str = Field(index=True)
    total: int = Field(default=0)
    created_at: datetime = Field(default_factory=utcnow)


class EmailJob(SQLModel, table=True):
    """A single queued email. The unit workers claim and deliver.

    Subject/body are stored already rendered, so delivery needs nothing but this
    row. Status transitions: queued → processing → (sent | back to queued for
    retry | failed once attempts are exhausted).
    """

    __tablename__ = "email_jobs"

    id: int | None = Field(default=None, primary_key=True)
    batch_id: int = Field(index=True, foreign_key="email_batches.id")
    recruiter_id: str = Field(index=True)

    to_email: str
    to_name: str | None = None
    subject: str = ""
    body: str = ""
    is_html: bool = False

    status: JobStatus = Field(default=JobStatus.queued, index=True)
    attempts: int = Field(default=0)
    max_attempts: int = Field(default=3)
    last_error: str | None = None

    # Earliest time a worker may pick this job up (used for retry backoff).
    scheduled_at: datetime = Field(default_factory=utcnow, index=True)
    created_at: datetime = Field(default_factory=utcnow, index=True)
    updated_at: datetime = Field(default_factory=utcnow)
