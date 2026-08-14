"""Transcript-derived delivery metrics.

These numbers appear on a recruiter's scorecard next to a hiring decision, so the tests
are about not overstating them: only the candidate's own words are counted, fillers are
matched as whole words, and anything that cannot be measured is None rather than zero.
"""

from __future__ import annotations

import pytest

from app.web.services import signals


def _session(*turns: dict, track: str = "chat") -> dict:
    return {"track": track, "transcript": list(turns)}


def _candidate(text: str, **overrides) -> dict:
    return {"role": "candidate", "content": text, **overrides}


def _interviewer(text: str) -> dict:
    return {"role": "interviewer", "content": text}


# ── which turns count ─────────────────────────────────────────────────────────


def test_only_the_candidates_turns_are_counted() -> None:
    """Counting the questions' words as the candidate's would make a terse candidate
    look verbose."""
    session = _session(
        _interviewer("Tell me about a difficult project you shipped recently please"),
        _candidate("I built a parser"),
    )
    metrics = signals.compute_speech_metrics(session)
    assert metrics["words"] == 4
    assert metrics["answers"] == 1


def test_blank_turns_are_ignored() -> None:
    session = _session(_candidate("  "), _candidate(""), _candidate("Real answer"))
    assert signals.compute_speech_metrics(session)["answers"] == 1


def test_no_candidate_turns_yields_none() -> None:
    """Zeros would read as "spoke, but badly" rather than "did not speak"."""
    assert signals.compute_speech_metrics(_session()) is None
    assert signals.compute_speech_metrics(_session(_interviewer("Question?"))) is None


def test_whitespace_only_answers_yield_none() -> None:
    assert signals.compute_speech_metrics(_session(_candidate("   \n  "))) is None


# ── fillers ───────────────────────────────────────────────────────────────────


def test_fillers_are_counted() -> None:
    assert signals.count_fillers("um I think uh maybe") == 2


def test_fillers_are_matched_as_whole_words() -> None:
    """Otherwise "umbrella" and "maximum" would be counted as hesitation."""
    assert signals.count_fillers("umbrella maximum erratic ahead") == 0


def test_multi_word_fillers_are_counted() -> None:
    assert signals.count_fillers("you know I mean it was kind of hard") == 3


def test_consecutive_fillers_are_all_counted() -> None:
    """A run of fillers is the clearest hesitation signal there is. The Express regex
    consumed the shared space and reported this as two."""
    assert signals.count_fillers("um um um") == 3


def test_ordinary_words_are_not_treated_as_fillers() -> None:
    """"so", "like" and "well" have legitimate uses; counting them would penalise normal
    speech."""
    assert signals.count_fillers("so I like it well enough") == 0


def test_punctuation_does_not_hide_a_filler() -> None:
    assert signals.count_fillers("Well, um, I think so.") == 1


def test_fillers_are_case_insensitive() -> None:
    assert signals.count_fillers("Um I think UH so") == 2


def test_filler_rate_is_per_hundred_words() -> None:
    """A raw count is meaningless without length."""
    text = "um " + " ".join(["word"] * 99)
    metrics = signals.compute_speech_metrics(_session(_candidate(text)))
    assert metrics["fillerCount"] == 1
    assert metrics["fillerPer100"] == 1.0


# ── derived metrics ───────────────────────────────────────────────────────────


def test_average_words_per_answer() -> None:
    session = _session(_candidate("one two three four"), _candidate("five six"))
    assert signals.compute_speech_metrics(session)["avgWordsPerAnswer"] == 3


def test_vocabulary_is_unique_over_total() -> None:
    session = _session(_candidate("the the the cat"))
    assert signals.compute_speech_metrics(session)["vocabularyPct"] == 50


def test_a_fully_varied_answer_scores_full_vocabulary() -> None:
    session = _session(_candidate("alpha beta gamma delta"))
    assert signals.compute_speech_metrics(session)["vocabularyPct"] == 100


@pytest.mark.parametrize("track,spoken", [
    ("voice", True), ("video_avatar", True), ("video", True), ("two_way", True),
    ("chat", False), ("chatbot", False),
])
def test_spoken_is_reported_per_track(track: str, spoken: bool) -> None:
    """Words per answer means something different out loud, so the UI needs to know."""
    session = _session(_candidate("an answer"), track=track)
    assert signals.compute_speech_metrics(session)["spoken"] is spoken


# ── response timing ───────────────────────────────────────────────────────────


def test_response_time_is_averaged_when_recorded() -> None:
    session = _session(
        _candidate("a", answerStartedAt="2027-01-01T00:00:00+00:00", submittedAt="2027-01-01T00:00:10+00:00"),
        _candidate("b", answerStartedAt="2027-01-01T00:01:00+00:00", submittedAt="2027-01-01T00:01:30+00:00"),
    )
    assert signals.compute_speech_metrics(session)["avgResponseSeconds"] == 20


def test_response_time_is_none_when_the_track_does_not_record_it() -> None:
    """Voice stamps every turn at finalise time, so there is no real span — a number
    here would look like thinking time."""
    assert signals.average_response_seconds(_session(_candidate("a"))) is None


def test_an_implausible_span_is_excluded() -> None:
    """A session left open overnight would skew the average to hours."""
    session = _session(
        _candidate("a", answerStartedAt="2027-01-01T00:00:00+00:00", submittedAt="2027-01-02T00:00:00+00:00"),
        _candidate("b", answerStartedAt="2027-01-01T00:00:00+00:00", submittedAt="2027-01-01T00:00:20+00:00"),
    )
    assert signals.average_response_seconds(session) == 20


def test_a_negative_span_is_excluded() -> None:
    session = _session(
        _candidate("a", answerStartedAt="2027-01-01T00:00:30+00:00", submittedAt="2027-01-01T00:00:00+00:00")
    )
    assert signals.average_response_seconds(session) is None


# ── sentiment normalisation ───────────────────────────────────────────────────


def test_a_clean_sentiment_payload_passes_through() -> None:
    result = signals.normalise_sentiment(
        {"overall": "positive", "confidence": 80, "clarity": 75, "positivity": 90, "summary": "Clear."}
    )
    assert result == {
        "overall": "positive",
        "confidence": 80,
        "clarity": 75,
        "positivity": 90,
        "summary": "Clear.",
    }


def test_an_unrecognised_overall_becomes_neutral() -> None:
    """The UI colours and labels this field; an unexpected string renders as an unstyled
    unknown state."""
    for value in ("enthusiastic", "", None, 42):
        assert signals.normalise_sentiment({"overall": value})["overall"] == "neutral"


def test_scores_are_clamped_to_the_reportable_range() -> None:
    result = signals.normalise_sentiment(
        {"confidence": 150, "clarity": -20, "positivity": 55.6}
    )
    assert result["confidence"] == 100
    assert result["clarity"] == 0
    assert result["positivity"] == 56


def test_non_numeric_scores_become_zero_not_a_crash() -> None:
    result = signals.normalise_sentiment({"confidence": "high", "clarity": None, "positivity": True})
    assert result["confidence"] == 0
    assert result["clarity"] == 0
    # True is an int in Python — excluded deliberately, since a boolean is not a score.
    assert result["positivity"] == 0


def test_a_missing_summary_says_so_rather_than_being_blank() -> None:
    assert signals.normalise_sentiment({})["summary"] == "No summary returned."
    assert signals.normalise_sentiment({"summary": "   "})["summary"] == "No summary returned."


def test_garbage_input_still_produces_a_usable_shape() -> None:
    for raw in (None, "text", 42, []):
        result = signals.normalise_sentiment(raw)
        assert result["overall"] == "neutral"
        assert set(result) == {"overall", "confidence", "clarity", "positivity", "summary"}


# ── the prompt ────────────────────────────────────────────────────────────────


def test_the_prompt_separates_communication_from_correctness() -> None:
    """Without both instructions the model conflates the two and the recruiter sees the
    same judgment twice — once here and once from the rubric."""
    prompt = signals.build_prompt(["I built a parser."])
    assert "not whether the answers are technically correct" in prompt
    assert "Judge from the words alone" in prompt


def test_the_prompt_numbers_the_answers() -> None:
    prompt = signals.build_prompt(["first", "second"])
    assert "Answer 1: first" in prompt
    assert "Answer 2: second" in prompt


def test_the_prompt_is_bounded() -> None:
    """A long interview's transcript would otherwise grow the request without bound."""
    prompt = signals.build_prompt(["word " * 20_000])
    assert len(prompt) < 14_000
