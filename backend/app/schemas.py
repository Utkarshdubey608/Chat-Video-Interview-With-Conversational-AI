"""Request/response bodies for the API (kept separate from the DB models)."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, EmailStr, Field

from app.models import JobStatus


# --- Templates ---
class TemplateBase(BaseModel):
    name: str = Field(default="Untitled template", max_length=120)
    subject: str = Field(default="", max_length=300)
    body: str = Field(default="")
    is_default: bool = False


class TemplateCreate(TemplateBase):
    recruiter_id: str = Field(min_length=1)


class TemplateUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    subject: str | None = Field(default=None, max_length=300)
    body: str | None = None
    is_default: bool | None = None


class TemplateRead(TemplateBase):
    id: int
    recruiter_id: str
    created_at: datetime
    updated_at: datetime


# --- Sending / queue ---
class Recipient(BaseModel):
    email: EmailStr
    name: str | None = None
    # Per-recipient template variables (e.g. their interview_link). Merged over
    # the request-level shared_context when rendering this recipient's email.
    context: dict[str, str] = Field(default_factory=dict)


class SendEmailRequest(BaseModel):
    recruiter_id: str = Field(min_length=1)
    recipients: list[Recipient] = Field(min_length=1)

    # Provide the template inline (subject + body) OR reference a saved one by
    # id. Inline wins when both are given.
    template_id: int | None = None
    subject: str | None = None
    body: str | None = None

    # Variables shared by every recipient (interview_title, recruiter_name, …).
    shared_context: dict[str, str] = Field(default_factory=dict)

    is_html: bool = True


class EnqueueResponse(BaseModel):
    batch_id: int
    queued: int


class JobRead(BaseModel):
    id: int
    to_email: EmailStr
    status: JobStatus
    attempts: int
    last_error: str | None = None


class BatchStatus(BaseModel):
    batch_id: int
    recruiter_id: str
    total: int
    queued: int
    processing: int
    sent: int
    failed: int
    jobs: list[JobRead]
