"""Fixed-slot interview timing — a port of `server/services/timing.ts`.

`tick` is what makes the timed tracks tamper-proof. Every phase boundary is decided
from SERVER timestamps recorded on the session, so the candidate's clock is irrelevant:
a client that lies about elapsed time, sleeps its tab, or replays a request gets the
same answer. It is idempotent and safe to call on every read as well as every write —
which is exactly how it stays correct across a candidate closing their laptop mid-answer
and coming back.

Two boundaries per question. Prep ends `prepSeconds` after `prepStartedAt`, at which
point the answer clock starts; the answer ends `answerSeconds` after `answerStartedAt`,
at which point whatever draft exists is auto-submitted. Both are computed from the
DEADLINE rather than from "now", so a candidate whose session was not read for ten
minutes is not charged those ten minutes against their next question.

Pure: mutates the session dict it is given and returns whether anything changed. No
storage, no HTTP.
"""

from __future__ import annotations

from datetime import datetime, timezone

# The conversational tracks have their own engine and no fixed question slots. Running
# this over them would invent deadlines for questions that do not exist yet.
CONVERSATIONAL_TRACKS = ("chatbot", "video_avatar", "two_way")

# A pathological session (contradictory timestamps) must not spin forever. Far above
# any real question count.
_MAX_TRANSITIONS = 10_000


def now_ms() -> int:
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def to_ms(value: object) -> int | None:
    """An ISO timestamp as epoch milliseconds, or None.

    Tolerates a naive value by reading it as UTC: every timestamp this engine writes is
    UTC, and a naive one that slipped in from elsewhere would otherwise be interpreted
    in the server's local zone and shift every deadline.
    """
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def to_iso(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat()


def total_questions(session: dict, template: dict) -> int:
    """How many questions the progress display should count against.

    The session's own list wins once it exists — an adaptive interview does not know
    its length until the questions are generated, and the template's number is the
    intent rather than the fact.
    """
    questions = session.get("questions") or []
    if questions:
        return len(questions)
    return (template.get("timing") or {}).get("numberOfQuestions") or 0


def _current(session: dict) -> dict | None:
    questions = session.get("questions") or []
    index = session.get("currentIndex") or 0
    return questions[index] if 0 <= index < len(questions) else None


def _auto_submit(question: dict, when_ms: int) -> None:
    """Submit whatever the candidate had when the clock ran out.

    The draft is promoted to the answer: a candidate who typed for two minutes and did
    not press submit has still answered, and discarding it would score them as silent.
    """
    if question.get("answerText") is None:
        question["answerText"] = question.get("draft") or ""
    question["submittedAt"] = to_iso(when_ms)
    question["autoSubmitted"] = True


def _start_next(session: dict, when_ms: int) -> None:
    """Move to the next question, or complete the session.

    The next question's prep clock starts at the moment the previous one ENDED, not
    "now" — otherwise a session that went unread for an hour would silently consume the
    next question's prep time.
    """
    session["currentIndex"] = (session.get("currentIndex") or 0) + 1
    following = _current(session)
    if following is not None:
        following["prepStartedAt"] = to_iso(when_ms)
    else:
        session["status"] = "completed"
        session.setdefault("completedAt", to_iso(when_ms))


def tick(session: dict, template: dict, at_ms: int | None = None) -> bool:
    """Advance through every boundary that has already elapsed. Returns True if changed."""
    if session.get("track") in CONVERSATIONAL_TRACKS:
        return False
    if session.get("status") != "in_progress":
        return False

    at_ms = now_ms() if at_ms is None else at_ms
    timing = template.get("timing") or {}
    prep_seconds = timing.get("prepSeconds") or 0
    answer_seconds = timing.get("answerSeconds") or 0
    mutated = False

    # The optional whole-interview cap. Checked first and returns immediately: once the
    # interview is over, no further per-question transition is meaningful.
    cap = timing.get("totalTimeCapSeconds")
    started = to_ms(session.get("startedAt"))
    if cap and started is not None and at_ms >= started + cap * 1000:
        current = _current(session)
        if current is not None and not current.get("submittedAt"):
            _auto_submit(current, at_ms)
        session["status"] = "completed"
        session["completedAt"] = to_iso(at_ms)
        return True

    for _ in range(_MAX_TRANSITIONS):
        question = _current(session)

        if question is None:
            # Ran off the end of the list: every question is done.
            session["status"] = "completed"
            session.setdefault("completedAt", to_iso(at_ms))
            mutated = True
            break

        if question.get("submittedAt"):
            # Defensive: a submitted question should never be the current one. Advance
            # from when it was submitted so the next question's clock is honest.
            _start_next(session, to_ms(question["submittedAt"]) or at_ms)
            mutated = True
            continue

        prep_started = to_ms(question.get("prepStartedAt"))
        if prep_started is None:
            # Not begun — waiting for the candidate to start.
            break

        answer_started = to_ms(question.get("answerStartedAt"))
        if answer_started is None:
            prep_deadline = prep_started + prep_seconds * 1000
            if at_ms >= prep_deadline:
                # Stamped at the DEADLINE, not now: the answer clock began the instant
                # prep ended, whether or not anyone was watching.
                question["answerStartedAt"] = to_iso(prep_deadline)
                mutated = True
                continue
            break

        answer_deadline = answer_started + answer_seconds * 1000
        if at_ms >= answer_deadline:
            _auto_submit(question, answer_deadline)
            _start_next(session, answer_deadline)
            mutated = True
            continue

        break

    return mutated


def compute_public_state(session: dict, template: dict, at_ms: int | None = None) -> dict:
    """The candidate-safe view of a session.

    Deliberately narrow: it carries the CURRENT question's id and text and nothing else
    from the list. A candidate must not be able to read ahead — seeing the remaining
    questions during prep would defeat the timing entirely.

    Call after `tick`, so the phase and countdown reflect boundaries already crossed.
    """
    at_ms = now_ms() if at_ms is None else at_ms
    timing = template.get("timing") or {}
    total = total_questions(session, template)
    question = _current(session)

    phase: str | None = None
    remaining = 0.0
    phase_total = 0

    if session.get("status") == "in_progress" and question is not None:
        answer_started = to_ms(question.get("answerStartedAt"))
        prep_started = to_ms(question.get("prepStartedAt"))

        if answer_started is not None:
            phase = "answer"
            phase_total = timing.get("answerSeconds") or 0
            remaining = phase_total - (at_ms - answer_started) / 1000
        elif prep_started is not None:
            phase = "prep"
            phase_total = timing.get("prepSeconds") or 0
            remaining = phase_total - (at_ms - prep_started) / 1000
        else:
            # Begun but not started: show a full prep clock rather than zero, so the
            # candidate is not told they have no time before they have begun.
            phase = "prep"
            phase_total = timing.get("prepSeconds") or 0
            remaining = phase_total

    import math

    return {
        "sessionId": session.get("id"),
        "status": session.get("status"),
        "track": session.get("track"),
        "phase": phase,
        # Ceiling, and never negative: a countdown that shows 0 while the answer is
        # still accepted reads as broken, and a negative one as a bug.
        "remainingSeconds": max(0, math.ceil(remaining)),
        "totalPhaseSeconds": phase_total,
        "question": (
            {"id": question.get("id"), "text": question.get("text")}
            if session.get("status") == "in_progress" and question is not None
            else None
        ),
        "progress": {
            "current": min((session.get("currentIndex") or 0) + 1, total or 1),
            "total": total,
        },
        "draft": (question or {}).get("draft") or (question or {}).get("answerText") or "",
        "timing": {
            "prepSeconds": timing.get("prepSeconds"),
            "answerSeconds": timing.get("answerSeconds"),
            "allowSkipPrep": timing.get("allowSkipPrep"),
            "allowEarlySubmit": timing.get("allowEarlySubmit"),
            "warningThresholdSeconds": timing.get("warningThresholdSeconds"),
        },
        "branding": template.get("branding"),
        "integrity": template.get("integrity"),
        "tabSwitchWarnings": session.get("tabSwitchCount") or 0,
        # An adaptive interview cannot generate its questions until the résumé exists,
        # so the client knows to ask for one first.
        "awaitingResume": template.get("questionSource") == "adaptive"
        and not session.get("resumeText"),
        "hasResume": bool(session.get("resumeText")),
    }


def answer_time_used(question: dict) -> int | None:
    """Seconds the candidate actually spent answering, for the recruiter's view.

    None rather than zero when either timestamp is missing: "not measured" and "answered
    instantly" are different facts, and a zero would be read as the latter.
    """
    started = to_ms(question.get("answerStartedAt"))
    submitted = to_ms(question.get("submittedAt"))
    if started is None or submitted is None:
        return None
    return max(0, round((submitted - started) / 1000))
