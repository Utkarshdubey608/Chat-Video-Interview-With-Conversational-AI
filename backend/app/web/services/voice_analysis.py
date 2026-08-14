"""Voice prosody analysis — the Gemini stand-in for Hume's discontinued API.

Ports the fallback half of `server/routes/avatar.ts`. Hume shut down the batch
Expression-Measurement API this feature was built on, so when a submit fails the
audio is analysed by Gemini instead and the result is **wrapped in Hume's exact
wire shape**. That wrapping is the whole trick: the browser's poll → predictions →
`buildSessionResult` pipeline then works completely unchanged, with no idea which
engine produced the scores.

Everything here is pure except `analyse_with_gemini`, so the sanitiser and the
envelope builder are directly testable — and they need to be, because the model's
output is free-form JSON that a client parser will trust.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from app.config import Settings
from app.web.services import gemini

logger = logging.getLogger("web.voice_analysis")

# The emotion vocabulary the client's `categorizeEmotion()` understands
# (src/types/hume.types.ts). A name outside this list is dropped rather than
# passed through: the client buckets by exact name, so an unknown one would be
# silently ignored downstream anyway — better to drop it here where it is logged.
VOICE_EMOTIONS = [
    # positive_high
    "Excitement", "Enthusiasm", "Pride", "Joy", "Amusement",
    # positive_calm
    "Calmness", "Contentment", "Satisfaction", "Interest",
    # cognitive
    "Concentration", "Determination", "Realization", "Curiosity", "Surprise (positive)",
    # social
    "Sympathy", "Nostalgia",
    # negative
    "Anxiety", "Confusion", "Disappointment", "Distress", "Embarrassment",
    "Fear", "Sadness", "Tiredness",
    # disengagement
    "Boredom", "Doubt", "Awkwardness",
]
_ALLOWED = {name.lower() for name in VOICE_EMOTIONS}

VOICE_PROMPT = f"""You are an expert vocal prosody analyst. Listen to this recording of a job-interview candidate answering questions.

Divide the recording into consecutive segments of roughly 4-6 seconds covering the ENTIRE duration. For EACH segment, score how the candidate's VOICE sounds (tone, energy, pace, steadiness, tremor) — not the meaning of the words — across 6 to 10 emotions chosen ONLY from this exact list:
{", ".join(VOICE_EMOTIONS)}

Rules:
- "begin" and "end" are seconds from the start of the audio; segments must be contiguous and cover the full duration.
- Scores are 0.0-1.0. Most real scores land between 0.05 and 0.6; only strong, unmistakable vocal signals exceed 0.6.
- For silent or non-speech segments use low-intensity Calmness/Boredom style scores rather than skipping the segment.
- Use ONLY the emotion names given, spelled exactly as written.
- Output ONLY a JSON array, no prose: [{{"begin": 0, "end": 5.2, "emotions": [{{"name": "Calmness", "score": 0.42}}, ...]}}, ...]"""

# Bounds the generation so one request cannot run away. ~60k tokens of JSON is far
# more than a full interview's segments need.
MAX_OUTPUT_TOKENS = 60_000


def _strip_code_fence(text: str) -> str:
    """Remove a ```json fence if the model added one despite being asked not to."""
    cleaned = text.strip()
    for prefix in ("```json", "```"):
        if cleaned.lower().startswith(prefix):
            cleaned = cleaned[len(prefix):]
            break
    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]
    return cleaned.strip()


def sanitise_segments(raw: Any) -> list[dict]:
    """Model output → trustworthy segments, sorted by start time.

    Every field is checked because this output is handed to a client parser that
    will plot and average it. A segment with `end <= begin` would produce a
    zero-or-negative duration and skew any time-weighted aggregate; a score
    outside 0-1 would break the client's colour scaling; an unrecognised emotion
    name would be dropped downstream without trace.

    A segment left with no valid emotions is discarded rather than kept empty — an
    empty segment reads as "no signal here" when the truth is "the model returned
    something unusable".
    """
    if not isinstance(raw, list):
        return []

    out: list[dict] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        try:
            begin = float(entry.get("begin"))
            end = float(entry.get("end"))
        except (TypeError, ValueError):
            continue
        if begin < 0 or end <= begin:
            continue

        emotions = []
        for item in entry.get("emotions") or []:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or "").strip()
            if not name or name.lower() not in _ALLOWED:
                continue
            try:
                score = float(item.get("score"))
            except (TypeError, ValueError):
                continue
            emotions.append({"name": name, "score": max(0.0, min(1.0, score))})

        if emotions:
            out.append({"begin": begin, "end": end, "emotions": emotions})

    return sorted(out, key=lambda s: s["begin"])


def wrap_as_batch_predictions(segments: list[dict], filename: str) -> list[dict]:
    """Put Gemini's segments inside Hume's BatchPrediction envelope.

    The shape is dictated by the client's parser (src/types/hume.types.ts) — it is
    not ours to simplify. Matching it exactly is what lets the browser stay
    unaware that Hume is not what answered.
    """
    return [
        {
            "source": {"type": "file", "filename": filename},
            "results": {
                "predictions": [
                    {
                        "file": filename,
                        "models": {
                            "prosody": {
                                "grouped_predictions": [
                                    {
                                        "id": "gemini-voice-0",
                                        "predictions": [
                                            {
                                                "time": {
                                                    "begin": s["begin"],
                                                    "end": s["end"],
                                                },
                                                "emotions": s["emotions"],
                                            }
                                            for s in segments
                                        ],
                                    }
                                ]
                            }
                        },
                    }
                ],
                "errors": [],
            },
        }
    ]


def candidate_mime_types(content_type: str) -> list[str]:
    """The mime types to try, in order.

    MediaRecorder produces `audio/webm` (Opus). Google's documented audio types do
    not include it, but Gemini accepts webm as a VIDEO container and still analyses
    the audio track — so a rejected audio mime is retried as `video/webm`. Without
    this the browser's own recording format fails outright.
    """
    primary = (content_type or "").split(";")[0].strip() or "audio/webm"
    ordered = [primary]
    if "video/webm" not in ordered:
        ordered.append("video/webm")
    return ordered


async def analyse_with_gemini(
    settings: Settings, audio: bytes, *, content_type: str
) -> list[dict]:
    """Score vocal prosody for one recording. Raises if no attempt succeeds."""
    import base64

    model = await gemini.resolve_model(settings)
    encoded = base64.b64encode(audio).decode()

    last_error: Exception | None = None
    for mime in candidate_mime_types(content_type):
        body = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {"inlineData": {"mimeType": mime, "data": encoded}},
                        {"text": VOICE_PROMPT},
                    ],
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "temperature": 0.2,
                "maxOutputTokens": MAX_OUTPUT_TOKENS,
            },
        }
        try:
            status, raw, _ = await gemini.generate_content_raw(
                settings, model=model, request_body=body
            )
            if status >= 400:
                raise RuntimeError(f"Gemini returned {status}")

            payload = json.loads(raw)
            text = (
                payload.get("candidates", [{}])[0]
                .get("content", {})
                .get("parts", [{}])[0]
                .get("text", "")
            )
            segments = sanitise_segments(json.loads(_strip_code_fence(text)))
            if not segments:
                raise RuntimeError("Gemini returned no usable prosody segments")
            return segments
        except Exception as exc:  # noqa: BLE001 - try the next mime, then give up
            last_error = exc
            logger.warning(
                "Gemini voice analysis with mime %r failed: %s", mime, exc
            )

    raise last_error or RuntimeError("Voice analysis failed")
