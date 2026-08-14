"""Scoring, and the transcript grouping it depends on.

The overall score is arithmetic done here, not a number from the model — so these tests
are the specification for how a recruiter's rubric weights turn into a hiring
recommendation. The other half is about refusing to fabricate: an interview that
captured nothing must not come back as a zero.
"""

from __future__ import annotations

import pytest

from app.web.services import conversation, scoring


def _kpi(kpi_id: str, weight: float = 1, enabled: bool = True) -> dict:
    return {
        "id": kpi_id,
        "label": kpi_id.title(),
        "description": f"How {kpi_id}",
        "weight": weight,
        "enabled": enabled,
    }


def _rubric(*kpis: dict) -> dict:
    return {"scoreScale": 100, "kpis": list(kpis) or [_kpi("communication"), _kpi("depth")]}


def _template(rubric: dict | None = None) -> dict:
    return {"rubric": rubric or _rubric()}


def _session(**overrides) -> dict:
    return {"id": "s1", "track": "chat", "questions": [], "transcript": [], **overrides}


# ── weighting ─────────────────────────────────────────────────────────────────


def test_equal_weights_average_evenly() -> None:
    rubric = _rubric(_kpi("a"), _kpi("b"))
    assert scoring.weighted_overall(rubric, {"a": 80, "b": 60}) == 70


def test_weights_are_normalised_so_only_ratios_matter() -> None:
    """A recruiter who sets every KPI to 2 means the same as every KPI at 1."""
    ones = _rubric(_kpi("a", 1), _kpi("b", 1))
    twos = _rubric(_kpi("a", 2), _kpi("b", 2))
    averages = {"a": 90, "b": 50}
    assert scoring.weighted_overall(ones, averages) == scoring.weighted_overall(twos, averages)


def test_a_heavier_weight_pulls_the_score() -> None:
    rubric = _rubric(_kpi("a", 3), _kpi("b", 1))
    # (90*3 + 50*1) / 4 = 80
    assert scoring.weighted_overall(rubric, {"a": 90, "b": 50}) == 80


def test_disabled_kpis_are_excluded_from_the_overall() -> None:
    rubric = _rubric(_kpi("a"), _kpi("b", enabled=False))
    assert scoring.weighted_overall(rubric, {"a": 80, "b": 0}) == 80


def test_zero_weighted_kpis_are_excluded() -> None:
    rubric = _rubric(_kpi("a", 1), _kpi("b", 0))
    assert scoring.weighted_overall(rubric, {"a": 80, "b": 0}) == 80


def test_a_rubric_with_no_weight_scores_zero() -> None:
    """A rubric with everything disabled has expressed no opinion; inventing a number
    would be worse than reporting none."""
    assert scoring.weighted_overall(_rubric(_kpi("a", enabled=False)), {"a": 90}) == 0
    assert scoring.weighted_overall(_rubric(_kpi("a", 0)), {"a": 90}) == 0
    assert scoring.weighted_overall({"kpis": []}, {}) == 0


def test_a_missing_average_counts_as_zero_in_the_overall() -> None:
    rubric = _rubric(_kpi("a"), _kpi("b"))
    assert scoring.weighted_overall(rubric, {"a": 100}) == 50


def test_a_non_numeric_weight_is_ignored() -> None:
    rubric = {"kpis": [_kpi("a"), {**_kpi("b"), "weight": "heavy"}]}
    assert scoring.weighted_overall(rubric, {"a": 80, "b": 0}) == 80


# ── averaging ─────────────────────────────────────────────────────────────────


def test_kpis_are_averaged_across_questions() -> None:
    per_question = [
        {"kpiScores": {"a": 80, "b": 60}},
        {"kpiScores": {"a": 60, "b": 40}},
    ]
    assert scoring.average_kpis(_rubric(_kpi("a"), _kpi("b")), per_question) == {"a": 70, "b": 50}


def test_a_question_missing_a_kpi_score_is_excluded_not_zeroed() -> None:
    """An unanswered question already drags the average down through its own zeros;
    counting a missing score again would penalise it twice."""
    per_question = [{"kpiScores": {"a": 80}}, {"kpiScores": {}}]
    assert scoring.average_kpis(_rubric(_kpi("a")), per_question) == {"a": 80}


def test_a_kpi_scored_nowhere_averages_to_zero() -> None:
    assert scoring.average_kpis(_rubric(_kpi("a")), [{"kpiScores": {}}]) == {"a": 0}


def test_only_enabled_kpis_appear_in_the_averages() -> None:
    rubric = _rubric(_kpi("a"), _kpi("b", enabled=False))
    averages = scoring.average_kpis(rubric, [{"kpiScores": {"a": 50, "b": 90}}])
    assert averages == {"a": 50}


def test_non_numeric_scores_are_ignored() -> None:
    per_question = [{"kpiScores": {"a": "high"}}, {"kpiScores": {"a": 60}}]
    assert scoring.average_kpis(_rubric(_kpi("a")), per_question) == {"a": 60}


# ── recommendation bands ──────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "score,expected",
    [
        (100, "strong_yes"), (80, "strong_yes"),
        (79, "yes"), (65, "yes"),
        (64, "maybe"), (50, "maybe"),
        (49, "no"), (0, "no"),
    ],
)
def test_recommendation_bands(score: int, expected: str) -> None:
    """Thresholds, not a model judgment, so equal scores always get equal
    recommendations."""
    assert scoring.recommendation_for(score) == expected


def test_the_models_recommendation_is_used_when_valid() -> None:
    session, template = _session(questions=[{"id": "q1"}]), _template()
    raw = {"perQuestion": [], "summary": "s", "recommendation": "maybe"}
    assert scoring.assemble_from_model(session, template, raw)["recommendation"] == "maybe"


def test_an_invented_recommendation_falls_back_to_the_bands() -> None:
    session, template = _session(questions=[{"id": "q1"}]), _template()
    raw = {"perQuestion": [], "summary": "s", "recommendation": "hire immediately"}
    report = scoring.assemble_from_model(session, template, raw)
    assert report["recommendation"] == scoring.recommendation_for(report["overallScore"])


# ── model output handling ─────────────────────────────────────────────────────


def test_scores_for_disabled_or_invented_kpis_are_discarded() -> None:
    """A model that scores a KPI the recruiter switched off must not influence the
    average."""
    session = _session(questions=[{"id": "q1"}])
    template = _template(_rubric(_kpi("a"), _kpi("b", enabled=False)))
    raw = {
        "perQuestion": [
            {
                "questionId": "q1",
                "scores": [
                    {"kpiId": "a", "score": 70},
                    {"kpiId": "b", "score": 100},
                    {"kpiId": "invented", "score": 100},
                ],
                "feedback": "ok",
            }
        ],
        "summary": "s",
    }
    report = scoring.assemble_from_model(session, template, raw)
    assert report["perQuestion"][0]["kpiScores"] == {"a": 70}


def test_out_of_range_scores_are_clamped() -> None:
    session = _session(questions=[{"id": "q1"}])
    raw = {
        "perQuestion": [
            {"questionId": "q1", "scores": [{"kpiId": "communication", "score": 900}], "feedback": ""}
        ],
        "summary": "s",
    }
    report = scoring.assemble_from_model(session, _template(), raw)
    assert report["perQuestion"][0]["kpiScores"]["communication"] == 100


def test_a_question_the_model_skipped_still_appears() -> None:
    """Its absence would make the report look shorter than the interview was."""
    session = _session(questions=[{"id": "q1"}, {"id": "q2"}])
    raw = {"perQuestion": [{"questionId": "q1", "scores": [], "feedback": "ok"}], "summary": "s"}
    report = scoring.assemble_from_model(session, _template(), raw)
    assert [p["questionId"] for p in report["perQuestion"]] == ["q1", "q2"]
    assert report["perQuestion"][1]["feedback"] == "No feedback returned."


def test_a_missing_summary_says_so() -> None:
    report = scoring.assemble_from_model(_session(), _template(), {"perQuestion": []})
    assert report["summary"] == "No summary returned."


def test_strengths_and_improvements_are_carried_when_present() -> None:
    raw = {"perQuestion": [], "summary": "s", "strengths": ["clear"], "improvements": ["depth"]}
    report = scoring.assemble_from_model(_session(), _template(), raw)
    assert report["strengths"] == ["clear"]
    assert report["improvements"] == ["depth"]


def test_non_list_strengths_are_dropped() -> None:
    raw = {"perQuestion": [], "summary": "s", "strengths": "clear"}
    assert "strengths" not in scoring.assemble_from_model(_session(), _template(), raw)


# ── not evaluated ─────────────────────────────────────────────────────────────


def test_a_not_evaluated_report_carries_no_recommendation() -> None:
    """A dropped call produced no evidence. A 0 with a "no" would be a judgment nobody
    made."""
    session = _session(questions=[{"id": "q1"}, {"id": "q2"}])
    report = scoring.not_evaluated_report(session, _template())

    assert report["notEvaluated"] is True
    assert "recommendation" not in report
    assert report["overallScore"] == 0
    assert len(report["perQuestion"]) == 2
    assert all(p["kpiScores"] == {} for p in report["perQuestion"])


def test_the_not_evaluated_summary_explains_what_to_do() -> None:
    report = scoring.not_evaluated_report(_session(), _template())
    assert "was not evaluated" in report["summary"]
    assert "retake" in report["summary"]


# ── the heuristic ─────────────────────────────────────────────────────────────


def test_the_heuristic_scores_zero_for_no_answer() -> None:
    assert scoring.heuristic_score("", "a") == 0
    assert scoring.heuristic_score("   ", "a") == 0


def test_the_heuristic_is_deterministic_across_processes() -> None:
    """Python's `hash()` is randomised per process, which would make the fallback report
    change between restarts for the same answers."""
    assert scoring.heuristic_score("a real answer here", "communication") == scoring.heuristic_score(
        "a real answer here", "communication"
    )


def test_the_heuristic_rewards_length_within_bounds() -> None:
    short = scoring.heuristic_score("brief", "a")
    long = scoring.heuristic_score(" ".join(["word"] * 150), "a")
    assert 0 < short < long <= 100


def test_the_heuristic_spreads_kpis_apart() -> None:
    """Identical numbers across every KPI would read as a real assessment that happened
    to agree."""
    answer = " ".join(["word"] * 40)
    scores = {scoring.heuristic_score(answer, kpi) for kpi in ("a", "b", "c", "d")}
    assert len(scores) > 1


def test_the_heuristic_report_labels_itself_degraded() -> None:
    session = _session(questions=[{"id": "q1", "answerText": "an answer"}])
    report = scoring.heuristic_report(session, _template())

    assert report["degraded"] is True
    assert "heuristic fallback" in report["summary"]
    assert "length only" in report["summary"]
    assert scoring.HEURISTIC_FEEDBACK in report["perQuestion"][0]["feedback"]


def test_the_heuristic_report_marks_unanswered_questions() -> None:
    session = _session(questions=[{"id": "q1", "answerText": ""}])
    report = scoring.heuristic_report(session, _template())
    assert report["perQuestion"][0]["feedback"] == scoring.NO_ANSWER_FEEDBACK
    assert set(report["perQuestion"][0]["kpiScores"].values()) == {0}


# ── transcript grouping ───────────────────────────────────────────────────────


def _interviewer(text: str, index: int | None = None, follow_up: bool = False) -> dict:
    turn = {"role": "interviewer", "content": text}
    if index is not None:
        turn["questionIndex"] = index
    if follow_up:
        turn["isFollowUp"] = True
    return turn


def _candidate(text: str, index: int | None = None, **extra) -> dict:
    turn = {"role": "candidate", "content": text, **extra}
    if index is not None:
        turn["questionIndex"] = index
    return turn


def test_questions_are_grouped_with_their_answers() -> None:
    session = _session(
        transcript=[
            _interviewer("Q one", 0),
            _candidate("A one", 0),
            _interviewer("Q two", 1),
            _candidate("A two", 1),
        ]
    )
    groups = conversation.primary_question_groups(session)
    assert [(g["index"], g["question"], g["answer"]) for g in groups] == [
        (0, "Q one", "A one"),
        (1, "Q two", "A two"),
    ]


def test_follow_up_answers_fold_into_their_parent_question() -> None:
    """A follow-up probes the same question; scoring it separately would double-count."""
    session = _session(
        transcript=[
            _interviewer("Q one", 0),
            _candidate("first part", 0),
            _interviewer("Say more?", 0, follow_up=True),
            _candidate("second part", 0),
        ]
    )
    groups = conversation.primary_question_groups(session)
    assert len(groups) == 1
    assert groups[0]["answer"] == "first part\n\nsecond part"


def test_an_unindexed_candidate_turn_is_attributed_to_the_last_question() -> None:
    """Voice transcripts arrive this way — the client stamps turns at finalise time with
    no indices. Dropping them would score a spoken interview as unanswered."""
    session = _session(
        transcript=[_interviewer("Q one", 0), _candidate("spoken answer")]
    )
    groups = conversation.primary_question_groups(session)
    assert groups[0]["answer"] == "spoken answer"


def test_a_candidate_turn_before_any_question_is_ignored() -> None:
    """There is nothing for it to belong to, and inventing a question would
    misattribute it."""
    session = _session(transcript=[_candidate("hello?")])
    assert conversation.primary_question_groups(session) == []


def test_greetings_and_wrap_ups_start_no_group() -> None:
    """An interviewer turn with no index is not a question."""
    session = _session(
        transcript=[
            _interviewer("Hello, ready?"),
            _interviewer("Q one", 0),
            _candidate("A one", 0),
            _interviewer("Thanks, that's all."),
        ]
    )
    groups = conversation.primary_question_groups(session)
    assert len(groups) == 1
    assert groups[0]["question"] == "Q one"


def test_an_unanswered_question_still_appears_with_an_empty_answer() -> None:
    session = _session(transcript=[_interviewer("Q one", 0), _interviewer("Q two", 1)])
    groups = conversation.primary_question_groups(session)
    assert [g["answer"] for g in groups] == ["", ""]


def test_groups_are_sorted_by_index() -> None:
    session = _session(
        transcript=[_interviewer("Q two", 1), _candidate("A", 1), _interviewer("Q one", 0)]
    )
    assert [g["index"] for g in conversation.primary_question_groups(session)] == [0, 1]


def test_blank_answers_are_not_joined_in() -> None:
    session = _session(
        transcript=[_interviewer("Q", 0), _candidate("  ", 0), _candidate("real", 0)]
    )
    assert conversation.primary_question_groups(session)[0]["answer"] == "real"


def test_auto_advanced_is_recorded_on_the_group() -> None:
    """It distinguishes running out of time from choosing to stop."""
    session = _session(
        transcript=[_interviewer("Q", 0), _candidate("partial", 0, autoAdvanced=True)]
    )
    assert conversation.primary_question_groups(session)[0]["autoAdvanced"] is True


def test_has_any_answer_detects_both_transcript_shapes() -> None:
    """One check covers a conversation with indices, the other a transcript with none. A
    false negative would produce a "not evaluated" report for a real interview."""
    assert conversation.has_any_answer(
        _session(transcript=[_interviewer("Q", 0), _candidate("A", 0)])
    )
    assert conversation.has_any_answer(_session(transcript=[_candidate("A")]))
    assert not conversation.has_any_answer(_session(transcript=[_interviewer("Q", 0)]))
    assert not conversation.has_any_answer(_session())
    assert not conversation.has_any_answer(_session(transcript=[_candidate("   ")]))


# ── conversation assembly ─────────────────────────────────────────────────────


def test_a_conversation_report_is_keyed_by_index() -> None:
    session = _session(
        track="voice",
        transcript=[_interviewer("Q one", 0), _candidate("A one", 0)],
    )
    raw = {
        "perQuestion": [
            {"questionIndex": 0, "scores": [{"kpiId": "communication", "score": 75}], "feedback": "good"}
        ],
        "summary": "s",
    }
    report = scoring.assemble_conversation_from_model(session, _template(), raw)
    assert report["perQuestion"][0]["questionId"] == "q0"
    assert report["perQuestion"][0]["kpiScores"]["communication"] == 75


def test_the_conversation_prompt_marks_follow_ups() -> None:
    """A model shown only grouped answers would lose the interviewer's probing, which is
    often what reveals whether an answer held up."""
    session = _session(
        transcript=[
            _interviewer("Q one", 0),
            _candidate("A one", 0),
            _interviewer("Say more?", 0, follow_up=True),
        ]
    )
    prompt = scoring.build_conversation_prompt(session, [_kpi("communication")])
    assert "[q0 · follow-up]" in prompt
    assert "fold any follow-ups into that question's score" in prompt


def test_the_fixed_prompt_carries_the_ideal_answer_notes() -> None:
    """So the model scores against what the recruiter was looking for."""
    session = _session(
        questions=[
            {"id": "q1", "text": "Why?", "idealAnswerNotes": "Mentions ownership", "answerText": "Because"}
        ]
    )
    prompt = scoring.build_fixed_prompt(session, [_kpi("depth")])
    assert "Ideal-answer notes: Mentions ownership" in prompt
    assert "judging only what the candidate actually said" in prompt


def test_an_unanswered_question_is_marked_in_the_prompt() -> None:
    session = _session(questions=[{"id": "q1", "text": "Why?"}])
    assert "(no answer given)" in scoring.build_fixed_prompt(session, [_kpi("depth")])


def test_the_prompt_restricts_the_model_to_enabled_kpi_ids() -> None:
    prompt = scoring.build_fixed_prompt(_session(), [_kpi("a"), _kpi("b")])
    assert "Use ONLY these KPI ids: a, b" in prompt
