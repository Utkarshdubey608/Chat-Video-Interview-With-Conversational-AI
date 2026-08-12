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


# --- Realtime (Gemini Live ephemeral tokens) ---
class LiveTokenRequest(BaseModel):
    """Ask for a token to open one Gemini Live session.

    No model, voice, or system instruction here on purpose: those are resolved
    server-side from the interview document and locked into the token, so a
    tampered client cannot influence them.
    """

    interview_id: str = Field(min_length=1, max_length=200)


class LiveTokenResponse(BaseModel):
    token: str
    # Handed back rather than hardcoded in the app: the token-authenticated
    # socket lives on a different API version from the minting endpoint, and
    # that mapping should be changeable without shipping a new build.
    ws_url: str = Field(serialization_alias="wsUrl")
    model: str
    expires_at: str = Field(serialization_alias="expiresAt")
    connect_by: str = Field(serialization_alias="connectBy")

    model_config = {"populate_by_name": True}


class PreviewTokenRequest(BaseModel):
    """Ask for a token to play one voice sample (the recruiter's voice picker)."""

    voice_name: str = Field(default="", max_length=60)
    # Capped again server-side in app.voice — never trust the client's limit.
    sample_text: str = Field(default="", max_length=400)


# --- Résumé rounds ---
class ResumeExtractRequest(BaseModel):
    """A PDF to transcribe. Base64 because it travels alongside JSON fields.

    The generous max_length is a first gate only: it bounds the *encoded* string,
    while `app.resume.MAX_PDF_BYTES` bounds the decoded file. Base64 inflates by
    4/3, so ~14 MB of text is the ceiling for a 10 MB PDF.
    """

    pdf_base64: str = Field(min_length=1, max_length=14_000_000, alias="pdfBase64")
    file_name: str | None = Field(default=None, max_length=300, alias="fileName")

    model_config = {"populate_by_name": True}


class ResumeExtractResponse(BaseModel):
    text: str
    char_count: int = Field(serialization_alias="charCount")
    # True when the résumé was longer than the server stores/prompts with, so the
    # UI can say so rather than silently showing a clipped résumé.
    truncated: bool = False

    model_config = {"populate_by_name": True}


class ResumeScoreRequest(BaseModel):
    """Score a résumé against its round's criteria and store the result.

    No criteria, role or prompt here on purpose: those are resolved server-side
    from the interview and its round, so a candidate cannot lower the bar they are
    being measured against. See `app.resume` for why the score is computed here at
    all.
    """

    interview_id: str = Field(min_length=1, max_length=200, alias="interviewId")
    resume_text: str = Field(min_length=30, max_length=200_000, alias="resumeText")
    file_name: str | None = Field(default=None, max_length=300, alias="fileName")

    model_config = {"populate_by_name": True}


class ResumeSkillScore(BaseModel):
    name: str
    required: bool = False
    score: int = 0
    evidence: str = ""


class ResumeScore(BaseModel):
    """The scorer's output.

    `alias` rather than `serialization_alias` (the convention elsewhere in this
    file) because this model is built FROM the camelCase map that
    `app.resume.normalise_score` produces and that Firestore stores — so the
    camelCase names have to validate on the way in as well as serialise on the
    way out.
    """

    overall_score: int = Field(alias="overallScore")
    verdict: str
    summary: str = ""
    experience_years: float | None = Field(default=None, alias="experienceYears")
    strengths: list[str] = Field(default_factory=list)
    gaps: list[str] = Field(default_factory=list)
    skills: list[ResumeSkillScore] = Field(default_factory=list)

    model_config = {"populate_by_name": True}


class ResumeScoreResponse(BaseModel):
    interview_id: str = Field(serialization_alias="interviewId")
    score: ResumeScore
    # How much of the résumé was actually scored, so the recruiter's raw-text
    # view and the score refer to the same thing.
    char_count: int = Field(serialization_alias="charCount")
    model: str

    model_config = {"populate_by_name": True}


# --- Interview evaluation (submitted by the candidate, scored server-side) ---
class EvaluateRequest(BaseModel):
    """A finished interview's question/answer pairs.

    No score, no prompt and no model here on purpose: all three are resolved
    server-side, so a submission cannot influence the number it is given.
    Entries are re-cleaned and capped in `app.evaluation.clean_responses`; the
    generous bound below only stops an absurd body being parsed at all.
    """

    responses: list[dict] = Field(min_length=1, max_length=200)


class EvaluateResponse(BaseModel):
    """Acknowledges the SUBMISSION, not a score.

    `status` is "scoring" when the answers were accepted and a background task is
    working on them, or "stored_without_score" when there was too little to score
    and that was recorded instead. Either way the answers are safely stored, which
    is what the candidate is waiting to hear.
    """

    interview_id: str = Field(serialization_alias="interviewId")
    status: str
    responses: int

    model_config = {"populate_by_name": True}


# --- Two-way interview (live recruiter <-> candidate call) ---
class TwoWayJoinResponse(BaseModel):
    """Everything the device needs to join the call, and nothing more.

    The Daily API key is never here. A room URL plus a short-lived token is all a
    participant needs, and both are useless once the room expires.
    """

    room_url: str = Field(serialization_alias="roomUrl")
    token: str
    # True only for the recruiter. Ownership is what allows admitting the person
    # waiting in the lobby, so the app uses this to decide which controls to show.
    is_owner: bool = Field(serialization_alias="isOwner")

    model_config = {"populate_by_name": True}
