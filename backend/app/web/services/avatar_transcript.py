"""Turning live avatar speech into scoreable transcript turns.

Ports `matchQuestionIndex` / `appendAvatarUtterance` from `server/routes/sessions.ts`.

The avatar track has a problem the other tracks do not: **nobody tells the server which
question is being asked.** Utterances arrive as plain text from live captions, in both
directions, and the avatar phrases things in its own voice around the scripted question.
So the question a given utterance corresponds to has to be recovered by matching it back
against the planned script.

Getting that wrong is not cosmetic — it decides which answer is scored against which
question. Hence the deliberately high similarity bar: an utterance that is not clearly
one of the planned questions is recorded as an acknowledgment rather than guessed at, and
the answers that follow stay attached to the last question actually recognised.

Pure. No storage, no HTTP.
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime, timezone

# A long interview is a few dozen turns. Well above that, and low enough that a client
# stuck in a loop cannot grow one document without bound.
MAX_TURNS = 800

# Below this length an utterance is "yes", "mm-hm" or a fragment — too little to match a
# question against without inventing a correspondence.
MIN_MATCHABLE_CHARS = 8

# How much of a planned question's wording must appear before an utterance is accepted as
# that question. High on purpose: a wrong match files an answer under the wrong question,
# and a missed match only costs an acknowledgment label.
MATCH_THRESHOLD = 0.75

# Nudges a tie toward a question that has not been asked yet, since the avatar is
# instructed to work through the script in order.
UNASKED_BONUS = 0.1

_PUNCTUATION = re.compile(r"[^\w\s]", re.UNICODE)
_WHITESPACE = re.compile(r"\s+")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalise(text: str) -> str:
    """Lowercased, punctuation-free, single-spaced — for comparison only."""
    return _WHITESPACE.sub(" ", _PUNCTUATION.sub(" ", (text or "").lower())).strip()


def match_question_index(session: dict, text: str) -> int | None:
    """Which planned question this utterance is, or None.

    Substring containment either way counts as certain: the avatar often wraps a question
    in a lead-in ("Great. So, tell me about…"), and the candidate's captions sometimes
    clip the start.

    Otherwise it is token overlap against the question's own wording, which is the right
    denominator — a long rambling lead-in should not dilute the match of a question fully
    contained inside it.
    """
    normalised = normalise(text)
    if len(normalised) < MIN_MATCHABLE_CHARS:
        return None

    tokens = set(normalised.split())
    questions = session.get("questions") or []
    already_asked = {
        turn.get("questionIndex")
        for turn in session.get("transcript") or []
        if turn.get("turnType") == "question"
    }

    best_index = -1
    best_score = 0.0

    for index, question in enumerate(questions):
        planned = normalise(question.get("text") or "")
        if not planned:
            continue

        if planned in normalised or normalised in planned:
            score = 1.0
        else:
            planned_tokens = planned.split()
            if not planned_tokens:
                continue
            hits = sum(1 for word in planned_tokens if word in tokens)
            score = hits / len(planned_tokens)

        if score < MATCH_THRESHOLD:
            continue

        weighted = score + (0 if index in already_asked else UNASKED_BONUS)
        if weighted > best_score:
            best_index = index
            best_score = weighted

    return best_index if best_index >= 0 else None


def append_utterance(session: dict, role: str, text: str) -> bool:
    """Record one utterance. Returns False when it was not stored.

    Interviewer speech that matches a planned question becomes a `question` turn and moves
    the cursor; anything else becomes an `acknowledgment`, which is never scored and never
    times anything.

    Candidate speech is bucketed under the current question — but only once a question has
    actually been asked. Greeting chatter ("yes, I'm ready") is kept for the transcript
    panel and left unbucketed, so it is not scored as an answer to question one.
    """
    transcript = session.setdefault("transcript", [])
    if len(transcript) >= MAX_TURNS:
        return False

    content = (text or "").strip()
    if not content:
        return False

    if role == "interviewer":
        index = match_question_index(session, content)
        already_asked = index is not None and any(
            turn.get("turnType") == "question" and turn.get("questionIndex") == index
            for turn in transcript
        )
        # A re-ask — the avatar repeating itself because the candidate did not hear — must
        # not create a second question turn, or the report would show it twice.
        is_question = index is not None and not already_asked

        turn = {
            "id": str(uuid.uuid4()),
            "role": "interviewer",
            "content": content,
            "turnType": "question" if is_question else "acknowledgment",
            "createdAt": _now(),
        }
        if index is not None:
            turn["questionIndex"] = index
            session["currentIndex"] = index

        transcript.append(turn)
        return True

    any_asked = any(turn.get("turnType") == "question" for turn in transcript)
    turn = {
        "id": str(uuid.uuid4()),
        "role": "candidate",
        "content": content,
        "createdAt": _now(),
    }
    if any_asked:
        turn["questionIndex"] = session.get("currentIndex") or 0

    transcript.append(turn)
    return True


def questions_asked(session: dict) -> int:
    """How many distinct planned questions have actually been asked.

    Returned to the client so it can show real progress through a conversation nobody is
    driving turn by turn.
    """
    return len(
        {
            turn.get("questionIndex")
            for turn in session.get("transcript") or []
            if turn.get("turnType") == "question"
        }
    )
