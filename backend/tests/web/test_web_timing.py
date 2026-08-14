"""The fixed-slot timing engine.

This is what makes the timed tracks tamper-proof, so the tests are about the properties
that hold regardless of what a client claims: deadlines come from stored server
timestamps, transitions are stamped at the DEADLINE rather than at "now", and calling
`tick` repeatedly changes nothing.
"""

from __future__ import annotations

import pytest

from app.web.services import timing

SECOND = 1000
T0 = 1_800_000_000_000  # a fixed epoch-ms origin, so every assertion is exact


def _template(**overrides) -> dict:
    return {
        "timing": {
            "prepSeconds": 30,
            "answerSeconds": 120,
            "allowSkipPrep": True,
            "allowEarlySubmit": True,
            "warningThresholdSeconds": 15,
            **overrides.pop("timing", {}),
        },
        "questionSource": "fixed",
        "branding": {"companyName": "Acme"},
        "integrity": {"detectTabSwitch": True},
        **overrides,
    }


def _question(index: int, **overrides) -> dict:
    return {"id": f"q{index}", "text": f"Question {index}", **overrides}


def _session(count: int = 2, **overrides) -> dict:
    return {
        "id": "s1",
        "track": "chat",
        "status": "in_progress",
        "currentIndex": 0,
        "questions": [_question(i) for i in range(count)],
        "startedAt": timing.to_iso(T0),
        **overrides,
    }



def _in_answer_phase(started_ms: int) -> dict:
    """A question whose answer clock is running.

    Both timestamps, because that is the only reachable state: `/begin` stamps
    `prepStartedAt` and only then can the answer clock start (by expiry or by
    `/skip-prep`). `answerStartedAt` alone never occurs, and `tick` treats a question
    with no `prepStartedAt` as not begun.
    """
    return {
        "prepStartedAt": timing.to_iso(started_ms - 30 * SECOND),
        "answerStartedAt": timing.to_iso(started_ms),
    }


# ── timestamp handling ────────────────────────────────────────────────────────


def test_iso_round_trips_through_milliseconds() -> None:
    assert timing.to_ms(timing.to_iso(T0)) == T0


def test_a_naive_timestamp_is_read_as_utc() -> None:
    """One that slipped in from elsewhere would otherwise be read in the server's local
    zone and shift every deadline by the offset."""
    assert timing.to_ms("2027-01-15T12:00:00") == timing.to_ms("2027-01-15T12:00:00+00:00")


def test_a_z_suffix_is_accepted() -> None:
    assert timing.to_ms("2027-01-15T12:00:00Z") == timing.to_ms("2027-01-15T12:00:00+00:00")


def test_a_missing_or_malformed_timestamp_is_none() -> None:
    for value in (None, "", "not a date", 12345, {}):
        assert timing.to_ms(value) is None


# ── the tick guard rails ──────────────────────────────────────────────────────


@pytest.mark.parametrize("track", ["chatbot", "video_avatar", "two_way"])
def test_conversational_tracks_are_never_ticked(track: str) -> None:
    """They have no fixed question slots; running this over them would invent deadlines
    for questions that do not exist yet."""
    session = _session(track=track)
    assert timing.tick(session, _template(), T0 + 999 * SECOND) is False
    assert session["currentIndex"] == 0
    assert session["status"] == "in_progress"


@pytest.mark.parametrize("status", ["created", "system_check", "completed", "expired"])
def test_only_an_in_progress_session_ticks(status: str) -> None:
    session = _session(status=status)
    assert timing.tick(session, _template(), T0 + 999 * SECOND) is False


def test_a_question_that_has_not_begun_does_not_advance() -> None:
    """No `prepStartedAt` means the candidate has not started; their clock must not run."""
    session = _session()
    assert timing.tick(session, _template(), T0 + 999 * SECOND) is False
    assert session["questions"][0].get("answerStartedAt") is None


# ── prep → answer ─────────────────────────────────────────────────────────────


def test_prep_expiry_starts_the_answer_clock_at_the_deadline() -> None:
    """Stamped at the deadline, not at "now": the answer clock began the instant prep
    ended, whether or not anyone was reading."""
    session = _session()
    session["questions"][0]["prepStartedAt"] = timing.to_iso(T0)

    # Read a full minute after prep should have ended.
    assert timing.tick(session, _template(), T0 + 90 * SECOND) is True
    assert session["questions"][0]["answerStartedAt"] == timing.to_iso(T0 + 30 * SECOND)


def test_prep_still_running_does_not_advance() -> None:
    session = _session()
    session["questions"][0]["prepStartedAt"] = timing.to_iso(T0)
    assert timing.tick(session, _template(), T0 + 29 * SECOND) is False
    assert session["questions"][0].get("answerStartedAt") is None


def test_the_boundary_is_inclusive() -> None:
    session = _session()
    session["questions"][0]["prepStartedAt"] = timing.to_iso(T0)
    assert timing.tick(session, _template(), T0 + 30 * SECOND) is True


# ── answer expiry ─────────────────────────────────────────────────────────────


def test_answer_expiry_promotes_the_draft_and_auto_submits() -> None:
    """A candidate who typed for two minutes and did not press submit has answered;
    discarding the draft would score them as silent."""
    session = _session()
    session["questions"][0].update({**_in_answer_phase(T0), "draft": "my partial answer"})

    assert timing.tick(session, _template(), T0 + 121 * SECOND) is True
    question = session["questions"][0]
    assert question["answerText"] == "my partial answer"
    assert question["autoSubmitted"] is True
    assert question["submittedAt"] == timing.to_iso(T0 + 120 * SECOND)


def test_an_existing_answer_is_not_overwritten_by_the_draft() -> None:
    session = _session()
    session["questions"][0].update({**_in_answer_phase(T0), "answerText": "submitted text", "draft": "stale"})
    timing.tick(session, _template(), T0 + 200 * SECOND)
    assert session["questions"][0]["answerText"] == "submitted text"


def test_an_empty_draft_becomes_an_empty_answer() -> None:
    session = _session()
    session["questions"][0].update(_in_answer_phase(T0))
    timing.tick(session, _template(), T0 + 200 * SECOND)
    assert session["questions"][0]["answerText"] == ""


def test_the_next_question_prep_starts_when_the_previous_one_ended() -> None:
    """Otherwise a session left unread would silently consume the next question's prep.

    Read just after question 0's deadline, so exactly one transition happens — reading
    much later correctly cascades through question 1 as well, which
    `test_several_elapsed_questions_are_caught_up_in_one_tick` covers. The five-second
    gap is what proves the stamp is the DEADLINE and not "now".
    """
    session = _session()
    session["questions"][0].update(_in_answer_phase(T0))

    timing.tick(session, _template(), T0 + 125 * SECOND)

    assert session["currentIndex"] == 1
    assert session["questions"][1]["prepStartedAt"] == timing.to_iso(T0 + 120 * SECOND)


def test_several_elapsed_questions_are_caught_up_in_one_tick() -> None:
    """A candidate who closed their laptop must come back to a correctly-advanced
    session, not one question at a time."""
    session = _session(count=3)
    session["questions"][0].update(_in_answer_phase(T0))

    timing.tick(session, _template(), T0 + 10_000 * SECOND)

    assert session["status"] == "completed"
    assert all(q.get("autoSubmitted") for q in session["questions"])


def test_the_session_completes_after_the_last_question() -> None:
    session = _session(count=1)
    session["questions"][0].update(_in_answer_phase(T0))

    timing.tick(session, _template(), T0 + 200 * SECOND)

    assert session["status"] == "completed"
    assert session["completedAt"] == timing.to_iso(T0 + 120 * SECOND)


def test_running_off_the_end_of_the_list_completes() -> None:
    session = _session(count=1, currentIndex=5)
    assert timing.tick(session, _template(), T0) is True
    assert session["status"] == "completed"


# ── idempotence ───────────────────────────────────────────────────────────────


def test_a_second_tick_at_the_same_moment_changes_nothing() -> None:
    """Safe to call on every read, which is what keeps it correct across reconnects."""
    session = _session(count=3)
    session["questions"][0].update(_in_answer_phase(T0))
    at = T0 + 500 * SECOND

    assert timing.tick(session, _template(), at) is True
    snapshot = str(session)
    assert timing.tick(session, _template(), at) is False
    assert str(session) == snapshot


def test_a_submitted_current_question_is_advanced_past() -> None:
    """Defensive: a submitted question should never be current, but if it is, advance
    from when it was submitted rather than stalling."""
    session = _session()
    session["questions"][0]["submittedAt"] = timing.to_iso(T0 + 10 * SECOND)

    assert timing.tick(session, _template(), T0 + 20 * SECOND) is True
    assert session["currentIndex"] == 1
    assert session["questions"][1]["prepStartedAt"] == timing.to_iso(T0 + 10 * SECOND)


# ── the overall cap ───────────────────────────────────────────────────────────


def test_the_total_cap_completes_the_session_and_submits_the_current_answer() -> None:
    session = _session(count=5)
    session["questions"][0].update({**_in_answer_phase(T0), "draft": "partial"})

    template = _template(timing={"totalTimeCapSeconds": 60})
    assert timing.tick(session, template, T0 + 61 * SECOND) is True

    assert session["status"] == "completed"
    assert session["questions"][0]["answerText"] == "partial"
    # Later questions are untouched — the interview ended, it was not rushed through.
    assert session["questions"][1].get("submittedAt") is None


def test_no_cap_means_no_cap() -> None:
    session = _session()
    session["questions"][0]["prepStartedAt"] = timing.to_iso(T0)
    timing.tick(session, _template(), T0 + 100_000 * SECOND)
    # Completed by running out of questions, not by a cap.
    assert session["status"] == "completed"


# ── the public state ──────────────────────────────────────────────────────────


def test_the_public_state_never_leaks_future_questions() -> None:
    """Reading ahead during prep would defeat the timing entirely."""
    session = _session(count=3)
    session["questions"][0]["prepStartedAt"] = timing.to_iso(T0)

    state = timing.compute_public_state(session, _template(), T0)

    assert state["question"] == {"id": "q0", "text": "Question 0"}
    assert "questions" not in state
    for value in state.values():
        assert "Question 1" not in str(value)


def test_the_prep_countdown_reflects_elapsed_time() -> None:
    session = _session()
    session["questions"][0]["prepStartedAt"] = timing.to_iso(T0)

    state = timing.compute_public_state(session, _template(), T0 + 10 * SECOND)
    assert state["phase"] == "prep"
    assert state["remainingSeconds"] == 20
    assert state["totalPhaseSeconds"] == 30


def test_the_answer_countdown_reflects_elapsed_time() -> None:
    session = _session()
    session["questions"][0].update(_in_answer_phase(T0))

    state = timing.compute_public_state(session, _template(), T0 + 20 * SECOND)
    assert state["phase"] == "answer"
    assert state["remainingSeconds"] == 100


def test_a_begun_but_unstarted_question_shows_a_full_prep_clock() -> None:
    """Telling a candidate they have no time before they have begun reads as broken."""
    state = timing.compute_public_state(_session(), _template(), T0)
    assert state["phase"] == "prep"
    assert state["remainingSeconds"] == 30


def test_the_countdown_never_goes_negative() -> None:
    session = _session()
    session["questions"][0].update(_in_answer_phase(T0))
    state = timing.compute_public_state(session, _template(), T0 + 9999 * SECOND)
    assert state["remainingSeconds"] == 0


def test_remaining_seconds_rounds_up() -> None:
    """A countdown showing 0 while the answer is still accepted reads as broken."""
    session = _session()
    session["questions"][0].update(_in_answer_phase(T0))
    state = timing.compute_public_state(session, _template(), T0 + 119_500)
    assert state["remainingSeconds"] == 1


def test_a_completed_session_has_no_phase_or_question() -> None:
    session = _session(status="completed")
    state = timing.compute_public_state(session, _template(), T0)
    assert state["phase"] is None
    assert state["question"] is None
    assert state["remainingSeconds"] == 0


def test_the_draft_is_returned_so_a_reconnect_resumes() -> None:
    session = _session()
    session["questions"][0]["draft"] = "half an answer"
    assert timing.compute_public_state(session, _template(), T0)["draft"] == "half an answer"


def test_a_submitted_answer_is_shown_when_there_is_no_draft() -> None:
    session = _session()
    session["questions"][0]["answerText"] = "submitted"
    assert timing.compute_public_state(session, _template(), T0)["draft"] == "submitted"


def test_progress_counts_from_one() -> None:
    session = _session(count=3, currentIndex=1)
    assert timing.compute_public_state(session, _template(), T0)["progress"] == {
        "current": 2,
        "total": 3,
    }


def test_progress_uses_the_template_count_before_questions_exist() -> None:
    """An adaptive interview does not know its length until the questions are
    generated."""
    session = _session(count=0)
    template = _template(timing={"numberOfQuestions": 5})
    assert timing.compute_public_state(session, template, T0)["progress"]["total"] == 5


def test_an_adaptive_template_awaits_a_resume() -> None:
    session = _session()
    template = _template(questionSource="adaptive")
    state = timing.compute_public_state(session, template, T0)
    assert state["awaitingResume"] is True
    assert state["hasResume"] is False


def test_a_resume_clears_the_await() -> None:
    session = _session(resumeText="Ada Lovelace, engineer")
    template = _template(questionSource="adaptive")
    state = timing.compute_public_state(session, template, T0)
    assert state["awaitingResume"] is False
    assert state["hasResume"] is True


def test_a_fixed_template_never_awaits_a_resume() -> None:
    assert timing.compute_public_state(_session(), _template(), T0)["awaitingResume"] is False


def test_the_state_carries_branding_and_integrity_for_the_candidate_ui() -> None:
    state = timing.compute_public_state(_session(), _template(), T0)
    assert state["branding"] == {"companyName": "Acme"}
    assert state["integrity"] == {"detectTabSwitch": True}


# ── answer time used ──────────────────────────────────────────────────────────


def test_answer_time_used_measures_the_span() -> None:
    question = {
        "answerStartedAt": timing.to_iso(T0),
        "submittedAt": timing.to_iso(T0 + 45 * SECOND),
    }
    assert timing.answer_time_used(question) == 45


def test_answer_time_used_is_none_when_unmeasured() -> None:
    """"Not measured" and "answered instantly" are different facts; zero would read as
    the latter."""
    assert timing.answer_time_used({}) is None
    assert timing.answer_time_used({"answerStartedAt": timing.to_iso(T0)}) is None
    assert timing.answer_time_used({"submittedAt": timing.to_iso(T0)}) is None


def test_answer_time_used_never_goes_negative() -> None:
    question = {
        "answerStartedAt": timing.to_iso(T0 + 10 * SECOND),
        "submittedAt": timing.to_iso(T0),
    }
    assert timing.answer_time_used(question) == 0
