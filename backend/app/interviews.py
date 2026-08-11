"""Reading interview documents, and deciding who may act on them.

The `interviews` collection is owned by the mobile app, and this module is almost
entirely a reader of it. Field names are the app's camelCase (see
`interview.dart`).

The one write is `save_resume_submission`. It is here rather than in
`app.resume` so that knowledge of this collection's field names stays in one
module, and it exists at all because a résumé score must NOT be written by the
client: `firestore.rules` lets an assigned candidate update their own interview
document, so a score the app computed would be a score the candidate chose.

Rounds (`tests/{testId}/rounds/{roundId}`, see `interview_round.dart`) are read
here too — an interview names its round, and the round holds the criteria a
résumé is scored against.

The access rules mirror `firestore.rules` deliberately — a recruiter owns an
interview by `recruiterId`, a candidate is assigned one by `candidateEmailLower`.
Re-checking here is not redundant: the client used to gate launches itself, and
once the device no longer holds a key the server is the only thing standing
between a candidate and someone else's interview session.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone

from app.config import Settings
from app.firebase import get_db

logger = logging.getLogger("interviews")

INTERVIEWS_COLLECTION = "interviews"
TESTS_COLLECTION = "tests"
ROUNDS_SUBCOLLECTION = "rounds"


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
    # Which test/round this assignment belongs to. Both empty on interviews
    # created before timelines existed — such an interview is the single implicit
    # round of a one-round test, and has no round document to read criteria from.
    test_id: str = ""
    round_id: str = ""
    round_kind: str = ""
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
        test_id=str(data.get("testId") or ""),
        round_id=str(data.get("roundId") or ""),
        round_kind=str(data.get("roundKind") or ""),
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


# ── Rounds ────────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class RoundCriteria:
    """What a round is judged against. Mirrors `RoundCriteria` in Dart."""

    required_skills: list[str] = field(default_factory=list)
    nice_to_have: list[str] = field(default_factory=list)
    min_years: float | None = None
    min_score: int | None = None

    @property
    def is_empty(self) -> bool:
        return (
            not self.required_skills
            and not self.nice_to_have
            and self.min_years is None
            and self.min_score is None
        )


def _as_str_list(value: object) -> list[str]:
    """Strings out of a Firestore array, dropping blanks and non-strings.

    The `isinstance` check is not defensive padding: `str(None)` is the literal
    "None", so a null left in a round's `requiredSkills` would otherwise be sent
    to the scorer as a skill named None and scored against.
    """
    if not isinstance(value, list):
        return []
    return [v.strip() for v in value if isinstance(v, str) and v.strip()]


def criteria_from_map(data: dict | None) -> RoundCriteria:
    """Build criteria from a round's `criteria` map. Tolerant of missing fields."""
    data = data or {}
    years = data.get("minYears")
    return RoundCriteria(
        required_skills=_as_str_list(data.get("requiredSkills")),
        nice_to_have=_as_str_list(data.get("niceToHave")),
        min_years=(
            float(years)
            if isinstance(years, (int, float)) and not isinstance(years, bool)
            else None
        ),
        min_score=_as_int(data.get("minScore")),
    )


def fetch_round_criteria(settings: Settings, interview: Interview) -> RoundCriteria:
    """The criteria for [interview]'s round, or empty criteria.

    Empty rather than an error for two legitimate cases: an interview created
    before timelines existed names no round, and a recruiter may simply not have
    set any criteria. Both mean "score it on the role in general", which is a
    worse screen than a configured one but a perfectly valid request — so a
    missing round must not fail the submission.
    """
    if not interview.test_id or not interview.round_id:
        return RoundCriteria()

    try:
        snapshot = (
            get_db(settings)
            .collection(TESTS_COLLECTION)
            .document(interview.test_id)
            .collection(ROUNDS_SUBCOLLECTION)
            .document(interview.round_id)
            .get()
        )
    except Exception as exc:  # noqa: BLE001 - a criteria read must never 500
        logger.warning(
            "could not read round %s/%s: %s",
            interview.test_id,
            interview.round_id,
            type(exc).__name__,
        )
        return RoundCriteria()

    if not snapshot.exists:
        return RoundCriteria()
    data = snapshot.to_dict() or {}
    return criteria_from_map(data.get("criteria"))


# ── The one write ─────────────────────────────────────────────────────────────


def save_resume_submission(
    settings: Settings,
    interview_id: str,
    *,
    resume: dict,
    result: dict,
) -> None:
    """Store a résumé submission and its score on the interview document.

    Written with the Admin SDK, which bypasses `firestore.rules` — that is the
    whole point. `resume.score` and `result.overallScore` decide whether someone
    progresses, and rules allow the candidate to write their own interview
    document, so these fields have to be set by something the candidate does not
    control.

    `resultPublished` is deliberately NOT touched: releasing a result to the
    candidate stays a recruiter action.
    """
    from firebase_admin import firestore as admin_firestore

    payload = {
        "resume": {**resume, "extractedAt": admin_firestore.SERVER_TIMESTAMP},
        "result": result,
        # A résumé round has no session to resume — submitting IS completing it.
        "status": "completed",
        "updatedAt": admin_firestore.SERVER_TIMESTAMP,
    }

    (
        get_db(settings)
        .collection(INTERVIEWS_COLLECTION)
        .document(interview_id)
        .set(payload, merge=True)
    )
