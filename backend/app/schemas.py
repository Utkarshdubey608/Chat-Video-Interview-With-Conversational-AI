"""Request/response bodies for the API."""

from __future__ import annotations

from pydantic import BaseModel, EmailStr, Field


# --- Templates ---
class TemplateCreate(BaseModel):
    name: str = Field(default="Untitled template", max_length=120)
    description: str | None = Field(default=None, max_length=300)
    subject: str = Field(min_length=1, max_length=300)
    body: str = Field(min_length=1)
    is_html: bool = True
    # The recruiter this template belongs to — only they will see it listed.
    owner_email: EmailStr
    # Their Firebase uid, kept alongside for traceability.
    recruiter_id: str | None = None


class TemplateRead(BaseModel):
    id: str
    name: str
    description: str | None = None
    subject: str
    body: str
    is_html: bool = True
    owner_email: str | None = None
    recruiter_id: str | None = None
    # "builtin" (ships with the service) or "custom" (saved in Firestore).
    source: str = "custom"
    # True for the template used when a send request names none.
    is_default: bool = False


class TemplateList(BaseModel):
    templates: list[TemplateRead]
    default_template_id: str
    # The {{ placeholders }} a template body may use.
    variables: dict[str, str]
    # Set when Firestore is unreachable — built-ins are still returned.
    warning: str | None = None


# --- Sending ---
class Recipient(BaseModel):
    email: EmailStr
    name: str | None = None
    # Per-recipient template variables (e.g. their own interview_link). Merged
    # over the request-level shared_context when rendering this email.
    context: dict[str, str] = Field(default_factory=dict)


class SendEmailRequest(BaseModel):
    recipients: list[Recipient] = Field(min_length=1, max_length=500)

    # Which template to use: a built-in id ("builtin:interview_invite") or a
    # Firestore template id. Omit to use the default template.
    template_id: str | None = None
    # The sending recruiter. When set, a custom template owned by someone else
    # is refused (404).
    owner_email: EmailStr | None = None

    # Optional one-off override — wins over the template's subject/body.
    subject: str | None = None
    body: str | None = None
    is_html: bool | None = None

    # Variables shared by every recipient (interview_title, recruiter_name, …).
    shared_context: dict[str, str] = Field(default_factory=dict)


class SendResult(BaseModel):
    email: EmailStr
    status: str  # "sent" | "failed"
    error: str | None = None


class SendResponse(BaseModel):
    total: int
    sent: int
    failed: int
    template_id: str
    provider: str  # "smtp" | "gmail_api" | "dry_run"
    subject_preview: str
    results: list[SendResult]
