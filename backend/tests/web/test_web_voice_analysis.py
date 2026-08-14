"""The Gemini prosody stand-in for Hume's discontinued API.

Two things are worth holding down hard here. The sanitiser consumes free-form
model output that a browser parser will then plot and average, so a bad segment
becomes a wrong chart rather than an error. And the envelope has to match Hume's
wire shape exactly, because matching it is the only reason the client works at all.
"""

from __future__ import annotations

from app.web.services import voice_jobs
from app.web.services.voice_analysis import (
    VOICE_EMOTIONS,
    _strip_code_fence,
    candidate_mime_types,
    sanitise_segments,
    wrap_as_batch_predictions,
)


def _segment(begin=0.0, end=5.0, emotions=None) -> dict:
    return {
        "begin": begin,
        "end": end,
        "emotions": emotions if emotions is not None else [{"name": "Calmness", "score": 0.4}],
    }


# ── sanitiser ─────────────────────────────────────────────────────────────────


def test_a_clean_segment_survives() -> None:
    out = sanitise_segments([_segment()])
    assert out == [{"begin": 0.0, "end": 5.0, "emotions": [{"name": "Calmness", "score": 0.4}]}]


def test_segments_are_sorted_by_start_time() -> None:
    """The client treats these as a timeline; out-of-order segments would draw a
    chart that jumps backwards."""
    out = sanitise_segments([_segment(begin=10, end=15), _segment(begin=0, end=5)])
    assert [s["begin"] for s in out] == [0.0, 10.0]


def test_zero_or_negative_duration_segments_are_dropped() -> None:
    """`end <= begin` would give a non-positive duration and skew any
    time-weighted average the client computes."""
    assert sanitise_segments([_segment(begin=5, end=5)]) == []
    assert sanitise_segments([_segment(begin=5, end=4)]) == []


def test_negative_start_times_are_dropped() -> None:
    assert sanitise_segments([_segment(begin=-1, end=4)]) == []


def test_scores_are_clamped_to_the_unit_range() -> None:
    """Out-of-range scores break the client's colour scaling."""
    out = sanitise_segments(
        [_segment(emotions=[{"name": "Joy", "score": 3.5}, {"name": "Fear", "score": -2}])]
    )
    assert out[0]["emotions"] == [
        {"name": "Joy", "score": 1.0},
        {"name": "Fear", "score": 0.0},
    ]


def test_unknown_emotion_names_are_dropped() -> None:
    """The client buckets by exact name, so an invented one is ignored downstream
    without trace — dropping it here is at least visible."""
    out = sanitise_segments(
        [_segment(emotions=[{"name": "Calmness", "score": 0.3}, {"name": "Hangry", "score": 0.9}])]
    )
    assert [e["name"] for e in out[0]["emotions"]] == ["Calmness"]


def test_emotion_names_match_case_insensitively_but_keep_their_spelling() -> None:
    """The model sometimes lower-cases a name. It is still the emotion it meant, so
    it is accepted — but passed on with whatever spelling the model used, which is
    what the Express version did."""
    out = sanitise_segments([_segment(emotions=[{"name": "calmness", "score": 0.3}])])
    assert out[0]["emotions"][0]["name"] == "calmness"


def test_a_segment_with_no_valid_emotions_is_discarded() -> None:
    """An empty segment reads as "no signal here" when the truth is "the model
    returned something unusable"."""
    assert sanitise_segments([_segment(emotions=[{"name": "Nonsense", "score": 0.5}])]) == []
    assert sanitise_segments([_segment(emotions=[])]) == []


def test_malformed_input_yields_nothing_rather_than_raising() -> None:
    for raw in (None, {}, "not a list", 42, [None], ["x"], [{"begin": "a", "end": "b"}]):
        assert sanitise_segments(raw) == []


def test_non_numeric_scores_are_dropped() -> None:
    out = sanitise_segments([_segment(emotions=[{"name": "Joy", "score": "high"}])])
    assert out == []


def test_every_prompt_emotion_is_accepted_by_the_sanitiser() -> None:
    """The prompt and the allowlist are two copies of one vocabulary; if they drift,
    the model is asked for names its own output filter then rejects."""
    out = sanitise_segments(
        [_segment(emotions=[{"name": name, "score": 0.5} for name in VOICE_EMOTIONS])]
    )
    assert len(out[0]["emotions"]) == len(VOICE_EMOTIONS)


# ── envelope ──────────────────────────────────────────────────────────────────


def test_envelope_matches_humes_nesting() -> None:
    """The path the client's parser walks (src/types/hume.types.ts). This shape is
    not ours to simplify."""
    wrapped = wrap_as_batch_predictions([_segment()], "interview.webm")

    assert wrapped[0]["source"] == {"type": "file", "filename": "interview.webm"}
    prediction = wrapped[0]["results"]["predictions"][0]
    assert prediction["file"] == "interview.webm"
    grouped = prediction["models"]["prosody"]["grouped_predictions"][0]
    assert grouped["id"] == "gemini-voice-0"
    assert grouped["predictions"][0]["time"] == {"begin": 0.0, "end": 5.0}
    assert grouped["predictions"][0]["emotions"] == [{"name": "Calmness", "score": 0.4}]
    assert wrapped[0]["results"]["errors"] == []


def test_envelope_survives_an_empty_segment_list() -> None:
    """A completed job with nothing in it must still be shaped like Hume's reply,
    or the client's parser throws instead of showing "no data"."""
    wrapped = wrap_as_batch_predictions([], "x.webm")
    grouped = wrapped[0]["results"]["predictions"][0]["models"]["prosody"]["grouped_predictions"][0]
    assert grouped["predictions"] == []


# ── mime negotiation ──────────────────────────────────────────────────────────


def test_webm_audio_falls_back_to_the_video_container() -> None:
    """MediaRecorder produces audio/webm, which Google's audio types exclude but
    which Gemini accepts as a video container. Without the retry, the browser's own
    recording format fails outright."""
    assert candidate_mime_types("audio/webm;codecs=opus") == ["audio/webm", "video/webm"]


def test_a_blank_content_type_defaults_to_webm() -> None:
    assert candidate_mime_types("") == ["audio/webm", "video/webm"]
    assert candidate_mime_types(None) == ["audio/webm", "video/webm"]


def test_video_webm_is_not_tried_twice() -> None:
    assert candidate_mime_types("video/webm") == ["video/webm"]


def test_other_types_are_tried_first_then_webm() -> None:
    assert candidate_mime_types("audio/wav") == ["audio/wav", "video/webm"]


# ── code fences ───────────────────────────────────────────────────────────────


def test_code_fences_are_stripped() -> None:
    """The prompt says "no prose", but models add fences anyway."""
    assert _strip_code_fence('```json\n[{"a": 1}]\n```') == '[{"a": 1}]'
    assert _strip_code_fence('```\n[1]\n```') == "[1]"
    assert _strip_code_fence('  [1]  ') == "[1]"


# ── job store helpers ─────────────────────────────────────────────────────────


def test_local_jobs_are_identified_by_prefix() -> None:
    """The prefix is load-bearing: the routes use it to tell a locally-run Gemini
    job from a real Hume job id and route the poll accordingly."""
    assert voice_jobs.is_local("gemvoice-abc")
    assert not voice_jobs.is_local("abc")
    assert not voice_jobs.is_local("")
    assert voice_jobs.new_id("abc") == "gemvoice-abc"


def test_predictions_decode_round_trip() -> None:
    import json

    payload = wrap_as_batch_predictions([_segment()], "x.webm")
    job = {"id": "gemvoice-1", "predictions": json.dumps(payload)}
    assert voice_jobs.predictions_of(job) == payload


def test_unreadable_predictions_yield_an_empty_list() -> None:
    """A 500 on the final poll would look like a server fault after the analysis
    actually succeeded."""
    assert voice_jobs.predictions_of({"id": "x", "predictions": "{not json"}) == []
    assert voice_jobs.predictions_of({"id": "x", "predictions": '{"a":1}'}) == []
    assert voice_jobs.predictions_of({"id": "x"}) == []
