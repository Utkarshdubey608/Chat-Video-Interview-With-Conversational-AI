"""The video-avatar track — ports the `/avatar/*` routes of `sessions.ts`.

A Tavus avatar conducts the interview over video. The server creates the conversation
from the recruiter's applied Setup config, so every candidate in a batch meets the same
avatar with the same script, and **the candidate's browser never receives a Tavus key**.

The client forwards live captions back here as they arrive; `avatar_transcript` turns
them into the same shape the other conversational tracks produce, so scoring, the speech
metrics and the results view all work unchanged.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Body, HTTPException, Request, status

from app.security import AuthedUser
from app.web.deps import RateLimitMediaWeb, WebUser, settings_of
from app.web.services import (
    app_settings,
    avatar_transcript,
    conversation,
    question_gen,
    session_store,
    tavus_candidate,
)
from app.web.store import get_store

logger = logging.getLogger("web.sessions.avatar")

router = APIRouter(prefix="/sessions", tags=["web:sessions"])

TIMES_OF_DAY = ("morning", "afternoon", "evening")

# One utterance. Live captions arrive in fragments; anything longer is a client bug.
MAX_UTTERANCE_CHARS = 4000

# How long to wait for an orphaned conversation to end before starting a replacement.
# Bounded because the candidate is waiting: Tavus concurrency limits can reject a new
# conversation while an old one is still counted live, but a slow teardown must not
# become a stuck interview.
ORPHAN_TEARDOWN_SECONDS = 2.5


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _load_avatar(settings, session_id: str, user: AuthedUser) -> tuple[dict, dict]:
    session, template = await session_store.load(settings, session_id, user)
    if session.get("track") != "video_avatar":
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "This interview does not use the video avatar"
        )
    return session, template


@router.post(
    "/{session_id}/avatar/start",
    summary="Start the avatar conversation",
    dependencies=[RateLimitMediaWeb],
)
async def start(
    session_id: str,
    request: Request,
    body: dict = Body(default={}),
    user: AuthedUser = WebUser,
) -> dict:
    """Create the Tavus conversation and return only its join URL."""
    settings = settings_of(request)
    session, template = await _load_avatar(settings, session_id, user)

    if session.get("status") in ("completed", "expired"):
        raise HTTPException(status.HTTP_409_CONFLICT, "The interview has already finished")

    config = await app_settings.avatar_config(settings)
    if not config or not config.get("replicaId"):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "No avatar is configured — apply one on the Setup page first.",
        )

    await _ensure_questions(settings, session, template, config)

    # A page refresh mid-call leaves an orphaned conversation. End it BEFORE creating the
    # replacement, or Tavus may reject the new one while the old is still counted live.
    if session.get("tavusConversationId"):
        await _end_orphan(settings, session["tavusConversationId"])
        session["tavusConversationId"] = None

    raw_time = body.get("timeOfDay")
    conversation_data = await tavus_candidate.create_conversation(
        settings,
        config,
        candidate_name=_real_name(session),
        questions=[q.get("text") or "" for q in session.get("questions") or []],
        time_of_day=raw_time if raw_time in TIMES_OF_DAY else None,
        # The résumé rides in as background so the avatar sounds informed — never as a
        # source of extra questions.
        resume_text=session.get("resumeText"),
    )

    session["tavusConversationId"] = conversation_data["conversation_id"]
    session["status"] = "in_progress"
    session.setdefault("startedAt", _now())
    session.setdefault("mode", "conversational")
    session.setdefault("transcript", [])
    await session_store.save(settings, session)

    return {
        "conversationUrl": conversation_data["conversation_url"],
        "totalQuestions": len(session.get("questions") or []),
    }


def _real_name(session: dict) -> str:
    """The candidate's name, or "" — never the "Candidate" placeholder.

    An avatar greeting someone as "Candidate" out loud is worse than not using a name.
    """
    name = ((session.get("candidate") or {}).get("name") or "").strip()
    return "" if name == "Candidate" else name


async def _ensure_questions(settings, session: dict, template: dict, config: dict) -> None:
    """Make sure a question plan exists — the avatar's strict script needs it up front."""
    if session.get("questions"):
        return

    if template.get("questionSource") == "adaptive":
        if not session.get("resumeText"):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "A résumé is required before starting"
            )
        adaptive = template.get("adaptive") or {}
        count = adaptive.get("numberOfQuestions") or 5
        try:
            generated = await question_gen.generate_from_resume_text(
                settings,
                resume_text=session["resumeText"],
                role=template.get("role") or "",
                seniority=template.get("seniority"),
                count=count,
                style=adaptive.get("style"),
                technical=adaptive.get("technicalCount"),
                non_technical=adaptive.get("nonTechnicalCount"),
                difficulty=adaptive.get("difficulty"),
                focus_topics=adaptive.get("focusTopics"),
            )
        except Exception as exc:  # noqa: BLE001 - interview them anyway
            logger.error("avatar question generation failed for %s: %s", session["id"], exc)
            generated = []
        if not generated:
            generated = question_gen.fallback_questions(template.get("role") or "this", count)

    elif config.get("fallbackQuestions"):
        # The recruiter's configured fallback script, used when the template supplies no
        # questions of its own.
        generated = [{"text": text} for text in config["fallbackQuestions"]]
    else:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "No questions are configured for this interview"
        )

    session["questions"] = [
        {
            "id": str(uuid.uuid4()),
            "text": question.get("text"),
            "category": question.get("category"),
            "idealAnswerNotes": question.get("idealAnswerNotes"),
            "autoSubmitted": False,
        }
        for question in generated
    ]
    session["currentIndex"] = 0


async def _end_orphan(settings, conversation_id: str) -> None:
    try:
        await asyncio.wait_for(
            tavus_candidate.end_conversation(settings, conversation_id),
            timeout=ORPHAN_TEARDOWN_SECONDS,
        )
    except (asyncio.TimeoutError, Exception):  # noqa: BLE001 - never block the candidate
        logger.info("orphaned conversation %s did not end in time", conversation_id)


@router.post("/{session_id}/avatar/transcript", summary="Forward a live utterance")
async def transcript(
    session_id: str,
    request: Request,
    body: dict = Body(...),
    user: AuthedUser = WebUser,
) -> dict:
    """Record one utterance from either speaker.

    Accepted just after completion too. Captions arrive with a lag, so the last answer
    often lands after the call has ended — dropping it would lose the very thing that
    makes the interview scoreable, and it re-triggers scoring when a placeholder report
    is already there.
    """
    settings = settings_of(request)
    session, template = await _load_avatar(settings, session_id, user)

    role = body.get("role")
    text = body.get("text")
    if role not in ("interviewer", "candidate") or not isinstance(text, str):
        return {"ok": False}
    if session.get("status") not in ("in_progress", "completed"):
        return {"ok": False}

    if not avatar_transcript.append_utterance(session, role, text.strip()[:MAX_UTTERANCE_CHARS]):
        return {"ok": False}

    await session_store.save(settings, session)

    if session.get("status") == "completed":
        await _rescore_if_placeholder(settings, session, template)

    return {
        "ok": True,
        "asked": avatar_transcript.questions_asked(session),
        "total": len(session.get("questions") or []),
    }


async def _rescore_if_placeholder(settings, session: dict, template: dict) -> None:
    """Discard a not-evaluated report once real answers arrive.

    That report is a placeholder saying "nothing was captured", not a judgment. A late
    caption proves otherwise, so it is deleted and the session scored for real —
    otherwise a completed interview would keep showing "not evaluated" alongside a
    transcript full of answers.
    """
    store = get_store(settings)
    existing = await store.reports.get(session["id"])
    if not existing or not existing.get("notEvaluated"):
        return
    if not conversation.has_any_answer(session):
        return

    await store.reports.delete(session["id"])
    await session_store.maybe_score(settings, session, template)


@router.post("/{session_id}/avatar/complete", summary="End the avatar interview")
async def complete(
    session_id: str, request: Request, user: AuthedUser = WebUser
) -> dict:
    """Close the conversation and finalise the session."""
    settings = settings_of(request)
    session, template = await _load_avatar(settings, session_id, user)

    if session.get("tavusConversationId"):
        await tavus_candidate.end_conversation(settings, session["tavusConversationId"])
        session["tavusConversationId"] = None

    if session.get("status") not in ("completed", "expired"):
        session["status"] = "completed"
        session["completedAt"] = _now()

    await session_store.save(settings, session)
    await session_store.maybe_score(settings, session, template)

    return {
        "ok": True,
        "hasAnswers": conversation.has_any_answer(session),
        "asked": avatar_transcript.questions_asked(session),
        "total": len(session.get("questions") or []),
    }
