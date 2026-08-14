"""Transcript-derived interview signals — a port of `server/services/signals.ts`.

Delivery metrics for the conversation tracks, computed from what is actually stored:
the candidate's transcript and per-answer timing.

**What is deliberately absent matters as much as what is here.** Acoustic prosody —
pitch, energy, tremor — needs the raw audio, and candidate sessions do not persist it.
So none is invented. The sentiment read is explicitly a read of the WORDS, labelled as
transcript-derived wherever it surfaces, because presenting a text analysis as vocal
emotion would misrepresent what the recruiter is looking at.

`compute_speech_metrics` is pure. `analyze_sentiment` calls a model and returns None
rather than raising — a missing communication read must not fail a scorecard.
"""

from __future__ import annotations

import json
import logging
import re

from app.config import Settings
from app.web.services import gemini

logger = logging.getLogger("web.signals")

# Tracks where the candidate SPOKE rather than typed. Reported so the UI can label the
# metrics honestly — words per answer means something different out loud.
SPOKEN_TRACKS = ("voice", "video_avatar", "video", "two_way")

# Only unambiguous fillers. "so", "like" and "well" are excluded on purpose: they have
# ordinary uses, and counting them would penalise normal speech as hesitation.
FILLER_SINGLE = ("um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mmm")
FILLER_MULTI = ("you know", "i mean", "kind of", "sort of", "you see")

# An implausible answer span — a session left open overnight — is excluded rather than
# skewing the average to hours.
_MAX_RESPONSE_MS = 60 * 60 * 1000

# Bounds the prompt. A long interview's transcript would otherwise grow the request
# without bound.
_MAX_TRANSCRIPT_CHARS = 12_000

SENTIMENT_SCHEMA = {
    "type": "object",
    "properties": {
        "overall": {"type": "string", "enum": ["positive", "neutral", "negative", "mixed"]},
        "confidence": {"type": "number"},
        "clarity": {"type": "number"},
        "positivity": {"type": "number"},
        "summary": {"type": "string"},
    },
    "required": ["overall", "confidence", "clarity", "positivity", "summary"],
    "propertyOrdering": ["overall", "confidence", "clarity", "positivity", "summary"],
}

_NON_WORD = re.compile(r"[^^\w\s']", re.UNICODE)
_WHITESPACE = re.compile(r"\s+")


def candidate_answers(session: dict) -> list[str]:
    """The candidate's own turns, non-empty, in order.

    Interviewer turns are excluded: counting the questions' words as the candidate's
    would make a terse candidate look verbose.
    """
    return [
        text
        for turn in session.get("transcript") or []
        if turn.get("role") == "candidate"
        for text in [(turn.get("content") or "").strip()]
        if text
    ]


def count_words(text: str) -> int:
    return len(text.split())


def average_response_seconds(session: dict) -> int | None:
    """Mean answer span, when the track recorded one.

    Only the chatbot track stamps `answerStartedAt` → `submittedAt` per turn. Voice
    stamps everything at finalise time, so there is no real span to measure and this
    returns None rather than a number that would look like thinking time.
    """
    spans = []
    for turn in session.get("transcript") or []:
        from app.web.services.timing import to_ms

        started = to_ms(turn.get("answerStartedAt"))
        submitted = to_ms(turn.get("submittedAt"))
        if started is None or submitted is None:
            continue
        span = submitted - started
        if 0 < span < _MAX_RESPONSE_MS:
            spans.append(span / 1000)

    if not spans:
        return None
    return round(sum(spans) / len(spans))


def _normalised(text: str) -> str:
    """Lowercased, punctuation-stripped, space-padded — for whole-word filler matching.

    The padding matters: matching " um " rather than "um" is what stops "umbrella" and
    "maximum" being counted as hesitation.
    """
    stripped = _NON_WORD.sub(" ", text.lower())
    return f" {_WHITESPACE.sub(' ', stripped).strip()} "


def count_fillers(text: str) -> int:
    """Whole-word filler count.

    A zero-width lookahead rather than a consuming scan, which is a deliberate FIX
    rather than a faithful port. Consecutive fillers share the space between them, so
    the Express regex (`/\\sum\\s/g`) consumes it and reports "um um um" as two. Since
    a run of fillers is the clearest possible hesitation signal, undercounting exactly
    there was the wrong way to be wrong.
    """
    haystack = _normalised(text)
    return sum(
        len(re.findall(rf"(?=\s{re.escape(filler)}\s)", haystack))
        for filler in FILLER_SINGLE + FILLER_MULTI
    )


def compute_speech_metrics(session: dict) -> dict | None:
    """Delivery metrics from the transcript.

    None when the candidate said or typed nothing: there is no meaningful measurement,
    and zeros would read as "spoke, but badly" rather than "did not speak".
    """
    answers = candidate_answers(session)
    if not answers:
        return None

    joined = " ".join(answers)
    words = count_words(joined)
    if words == 0:
        return None

    filler_count = count_fillers(joined)
    tokens = _normalised(joined).split()
    unique = len(set(tokens))

    return {
        "words": words,
        "answers": len(answers),
        "avgWordsPerAnswer": round(words / len(answers)),
        "fillerCount": filler_count,
        # Per 100 words, to one decimal: a raw count is meaningless without length.
        "fillerPer100": round(filler_count / words * 1000) / 10 if words else 0,
        "vocabularyPct": round(unique / len(tokens) * 100) if tokens else 0,
        "avgResponseSeconds": average_response_seconds(session),
        "spoken": session.get("track") in SPOKEN_TRACKS,
    }


def _clamp(value: object) -> int:
    """A 0-100 integer from whatever the model returned."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return max(0, min(100, round(value)))


def build_prompt(answers: list[str]) -> str:
    """The sentiment prompt.

    It says "judge from the words alone" because that is what this can honestly do, and
    "not whether the answers are technically correct" because that is the rubric's job —
    without both, the model conflates communication with competence and the recruiter
    sees the same judgment twice.
    """
    transcript = "\n".join(
        f"Answer {index + 1}: {answer}" for index, answer in enumerate(answers)
    )[:_MAX_TRANSCRIPT_CHARS]

    return (
        "You are analysing ONLY the candidate's answers from an interview transcript to "
        "gauge how they COMMUNICATED (not whether the answers are technically correct). "
        "Judge from the words alone.\n\n"
        "Return:\n"
        "- overall: the dominant sentiment/tone (positive, neutral, negative, or mixed)\n"
        "- confidence (0-100): how self-assured and decisive the wording is\n"
        "- clarity (0-100): how clear, structured and articulate the responses are\n"
        "- positivity (0-100): how positive and constructive the tone is\n"
        "- summary: one or two sentences on their communication style.\n\n"
        f'CANDIDATE ANSWERS:\n"""\n{transcript}\n"""'
    )


def normalise_sentiment(raw: object) -> dict:
    """Model output → a trustworthy `SentimentSignals`.

    `overall` falls back to `neutral` rather than passing an unrecognised value through:
    the UI colours and labels this field, and an unexpected string would render as an
    unstyled unknown state.
    """
    data = raw if isinstance(raw, dict) else {}
    overall = data.get("overall")
    if overall not in ("positive", "negative", "mixed"):
        overall = "neutral"

    summary = data.get("summary")
    return {
        "overall": overall,
        "confidence": _clamp(data.get("confidence")),
        "clarity": _clamp(data.get("clarity")),
        "positivity": _clamp(data.get("positivity")),
        "summary": summary.strip()
        if isinstance(summary, str) and summary.strip()
        else "No summary returned.",
    }


async def analyze_sentiment(settings: Settings, session: dict) -> dict | None:
    """The communication read, or None.

    Never raises: a scorecard is still useful without it, and failing the whole
    evaluation because one optional signal was unavailable would be worse than omitting
    it.
    """
    if not await gemini.is_enabled(settings):
        return None

    answers = candidate_answers(session)
    if not answers:
        return None

    try:
        text = await gemini.generate_text(
            settings,
            contents=[{"role": "user", "parts": [{"text": build_prompt(answers)}]}],
            response_mime_type="application/json",
            response_schema=SENTIMENT_SCHEMA,
            temperature=0.2,
        )
        return normalise_sentiment(json.loads(text or "{}"))
    except Exception as exc:  # noqa: BLE001 - an optional signal, never a failure
        logger.warning("sentiment analysis failed: %s", exc)
        return None
