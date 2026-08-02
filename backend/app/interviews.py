"""Reading interview documents, and deciding who may act on them.

The `interviews` collection is owned by the mobile app; this module only reads it.
Field names are the app's camelCase (see `interview.dart`).

The access rules mirror `firestore.rules` deliberately — a recruiter owns an
interview by `recruiterId`, a candidate is assigned one by `candidateEmailLower`.
Re-checking here is not redundant: the client used to gate launches itself, and
once the device no longer holds a key the server is the only thing standing
between a candidate and someone else's interview session.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone

from app.config import Settings
from app.firebase import get_db

INTERVIEWS_COLLECTION = "interviews"


class InterviewNotFound(LookupError):
    """No such interview document."""


class InterviewAccessDenied(PermissionError):
    """The caller is neither the assigned candidate nor the owning recruiter."""


class InterviewNotLaunchable(RuntimeError):
    """Access is fine, but the interview cannot start right now."""


@dataclass(frozen=True)
class Interview:
    """The subset of the document this service needs. Others are ignored."""

    id: str
    recruiter_id: str
    candidate_email_lower: str
    candidate_name: str | None
    recruiter_name: str | None
    title: str
    prompt: str
    questions: list[str] = field(default_factory=list)
    language: str = "English"
    voice_name: str | None = None
    voice_persona_id: str | None = None
    duration_minutes: int = 15
    status: str = "pending"
    available_from: datetime | None = None
    expires_at: datetime | None = None
    max_attempts: int | None = None
    attempts_used: int = 0

    # --- launch eligibility (mirrors Interview.isAccessible in Dart) --------
    @property
    def is_expired(self) -> bool:
        return self.expires_at is not None and _now() > self.expires_at

    @property
    def is_not_yet_available(self) -> bool:
        return self.available_from is not None and _now() < self.available_from

    @property
    def has_attempts_left(self) -> bool:
        return self.max_attempts is None or self.attempts_used < self.max_attempts

    def ensure_launchable(self) -> None:
        """Raise with a candidate-readable reason if this cannot start now."""
        if self.is_not_yet_available:
            raise InterviewNotLaunchable("This interview is not open yet.")
        if self.is_expired:
            raise InterviewNotLaunchable("This interview has expired.")
        if not self.has_attempts_left:
            raise InterviewNotLaunchable(
                "You have used all attempts for this interview."
            )


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _as_datetime(value: object) -> datetime | None:
    """Firestore timestamps arrive as datetimes; anything else is ignored.

    Naive values are treated as UTC so comparisons never raise.
    """
    if not isinstance(value, datetime):
        return None
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _as_int(value: object, default: int | None = None) -> int | None:
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else default


def from_document(doc_id: str, data: dict) -> Interview:
    """Build an `Interview` from raw document data. Tolerant of missing fields."""
    email = data.get("candidateEmailLower") or data.get("candidateEmail") or ""

    return Interview(
        id=doc_id,
        recruiter_id=str(data.get("recruiterId") or ""),
        candidate_email_lower=str(email).strip().lower(),
        candidate_name=data.get("candidateName"),
        recruiter_name=data.get("recruiterName"),
        title=str(data.get("title") or "Interview"),
        prompt=str(data.get("prompt") or ""),
        questions=[str(q) for q in (data.get("questions") or [])],
        language=str(data.get("language") or "English"),
        voice_name=data.get("voiceName"),
        voice_persona_id=data.get("voicePersonaId"),
        duration_minutes=_as_int(data.get("durationMinutes"), 15) or 15,
        status=str(data.get("status") or "pending"),
        available_from=_as_datetime(data.get("availableFrom")),
        expires_at=_as_datetime(data.get("expiresAt")),
        max_attempts=_as_int(data.get("maxAttempts")),
        attempts_used=_as_int(data.get("attemptsUsed"), 0) or 0,
    )


def fetch(settings: Settings, interview_id: str) -> Interview:
    """Load one interview, or raise `InterviewNotFound`."""
    snapshot = (
        get_db(settings).collection(INTERVIEWS_COLLECTION).document(interview_id).get()
    )
    if not snapshot.exists:
        raise InterviewNotFound(f"No interview with id {interview_id!r}.")
    return from_document(snapshot.id, snapshot.to_dict() or {})


def is_assigned_candidate(interview: Interview, *, uid: str, email: str | None) -> bool:
    """Assignment is by email — the app never stores a candidate uid."""
    del uid  # kept for signature symmetry with is_owning_recruiter
    if not email or not interview.candidate_email_lower:
        return False
    return email.strip().lower() == interview.candidate_email_lower


def is_owning_recruiter(interview: Interview, *, uid: str) -> bool:
    return bool(uid) and uid == interview.recruiter_id


def require_candidate(interview: Interview, *, uid: str, email: str | None) -> None:
    """The assigned candidate may launch. The owning recruiter may too, so a
    recruiter can preview their own interview end-to-end."""
    if is_assigned_candidate(interview, uid=uid, email=email):
        return
    if is_owning_recruiter(interview, uid=uid):
        return
    raise InterviewAccessDenied("This interview is not assigned to you.")


def require_recruiter(interview: Interview, *, uid: str) -> None:
    if not is_owning_recruiter(interview, uid=uid):
        raise InterviewAccessDenied("You do not own this interview.")
