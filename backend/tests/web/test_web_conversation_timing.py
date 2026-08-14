"""The conversational track's per-turn timing.

Different from the fixed-slot engine in one way that decides whether the timing is fair:
the clock is armed when the CLIENT presents the question, not when the server appends it.
A "Thinking…" indicator and a spoken acknowledgment must not come out of the candidate's
answer time.
"""

from __future__ import annotations

import pytest

from app.web.services import conversation
from app.web.services.timing import to_iso

SECOND = 1000
T0 = 1_800_000_000_000


def _template(**overrides) -> dict:
    return {
        "track": "chatbot",
        "mode": "conversational",
        "questionSource": "adaptive",
        "adaptive": {"numberOfQuestions": 5},
        "timing": {"answerSeconds": 120, "warningThresholdSeconds": 15, "allowEarlySubmit": True},
        "chatbotTimer": {
            "enabled": True,
            "perQuestionSeconds": 120,
            "timeFollowUps": True,
            "followUpSeconds": 90,
            "includeThinkingPhase": False,
            "thinkingSeconds": 20,
            "warningThresholdSeconds": 15,
            "allowEarlySubmit": True,
            "autoSubmitOnExpiry": True,
        },
        "branding": {"companyName": "Acme"},
        "integrity": {"detectTabSwitch": True},
        **overrides,
    }


def _turn(**overrides) -> dict:
    return {
        "id": "t1",
        "role": "interviewer",
        "content": "Tell me about a project.",
        "turnType": "question",
        "questionIndex": 0,
        **overrides,
    }


def _session(*turns: dict, **overrides) -> dict:
    return {
        "id": "s1",
        "track": "chatbot",
        "status": "in_progress",
        "currentIndex": 0,
        "transcript": list(turns),
        **overrides,
    }


# ── which turns are timed ─────────────────────────────────────────────────────


@pytest.mark.parametrize("turn_type", ["question", "follow_up"])
def test_questions_and_follow_ups_are_timed(turn_type: str) -> None:
    assert conversation.is_question_turn(_turn(turnType=turn_type))


@pytest.mark.parametrize("turn_type", ["greeting", "readiness", "acknowledgment", "wrap_up"])
def test_conversational_furniture_is_untimed(turn_type: str) -> None:
    """A countdown on "Are you ready to begin?" would rush a candidate before the
    interview has started."""
    assert not conversation.is_question_turn(_turn(turnType=turn_type))
    assert conversation.turn_timing(_template(), _turn(turnType=turn_type)) is None


def test_a_legacy_turn_is_timed_when_it_names_a_question() -> None:
    """Turns written before `turnType` existed carry only a question index."""
    assert conversation.is_question_turn({"questionIndex": 0})
    assert not conversation.is_question_turn({})


# ── timer resolution ──────────────────────────────────────────────────────────


def test_the_explicit_timer_wins() -> None:
    timing = conversation.turn_timing(_template(), _turn())
    assert timing["answerSeconds"] == 120
    assert timing["autoSubmitOnExpiry"] is True


def test_a_chat_template_taken_as_a_chatbot_inherits_its_fixed_timing() -> None:
    """The candidate can switch tracks on the entry screen; without this the recruiter's
    per-question limit would silently stop applying the moment they did."""
    template = _template(track="chat", chatbotTimer=None)
    timing = conversation.turn_timing(template, _turn())
    assert timing["answerSeconds"] == 120
    assert conversation.timer_enabled(template) is True


def test_a_chatbot_template_with_no_timer_is_untimed() -> None:
    template = _template(track="chatbot", chatbotTimer=None, mode="conversational")
    assert conversation.effective_chatbot_timer(template) is None
    assert conversation.timer_enabled(template) is False
    assert conversation.turn_timing(template, _turn()) is None


def test_follow_ups_use_their_own_window() -> None:
    timing = conversation.turn_timing(_template(), _turn(turnType="follow_up"))
    assert timing["answerSeconds"] == 90


def test_follow_ups_fall_back_to_the_question_window() -> None:
    template = _template()
    template["chatbotTimer"]["followUpSeconds"] = None
    assert conversation.turn_timing(template, _turn(turnType="follow_up"))["answerSeconds"] == 120


def test_untimed_follow_ups_are_respected() -> None:
    """A recruiter who timed the questions but not the follow-ups meant the probing to be
    unhurried."""
    template = _template()
    template["chatbotTimer"]["timeFollowUps"] = False
    assert conversation.turn_timing(template, _turn(turnType="follow_up")) is None
    # The primary question is still timed.
    assert conversation.turn_timing(template, _turn()) is not None


def test_a_per_question_override_wins_for_a_fixed_set() -> None:
    template = _template(questionSource="fixed")
    template["chatbotTimer"]["perQuestionOverrides"] = {"q-b": 300}
    timing = conversation.turn_timing(
        template, _turn(questionIndex=1), fixed_question_ids=["q-a", "q-b"]
    )
    assert timing["answerSeconds"] == 300


def test_an_override_for_another_question_does_not_apply() -> None:
    template = _template(questionSource="fixed")
    template["chatbotTimer"]["perQuestionOverrides"] = {"q-b": 300}
    timing = conversation.turn_timing(
        template, _turn(questionIndex=0), fixed_question_ids=["q-a", "q-b"]
    )
    assert timing["answerSeconds"] == 120


def test_the_legacy_timed_mode_is_supported() -> None:
    template = _template(
        chatbotTimer=None,
        track="chatbot",
        mode="timed",
        conversationTiming={
            "thinkingSeconds": 30,
            "perQuestionSeconds": 90,
            "allowSkipThinking": True,
            "allowEarlySubmit": True,
            "warningThresholdSeconds": 10,
        },
    )
    timing = conversation.turn_timing(template, _turn())
    assert timing["thinkingSeconds"] == 30
    assert timing["answerSeconds"] == 90
    assert timing["allowSkipThinking"] is True
    # No opt-out in the legacy mode — a window that expired without submitting would
    # strand the interview.
    assert timing["autoSubmitOnExpiry"] is True


def test_the_thinking_phase_is_off_unless_enabled() -> None:
    assert conversation.turn_timing(_template(), _turn())["thinkingSeconds"] == 0

    template = _template()
    template["chatbotTimer"]["includeThinkingPhase"] = True
    timing = conversation.turn_timing(template, _turn())
    assert timing["thinkingSeconds"] == 20
    assert timing["allowSkipThinking"] is True


# ── arming the clock ──────────────────────────────────────────────────────────


def test_the_clock_starts_when_the_client_presents_the_question() -> None:
    """Not when the server appends the turn — the indicator and any acknowledgment must
    not eat into the answer window."""
    session = _session(_turn())
    assert conversation.reveal_timed_turn(session, _template(), T0) is True
    assert session["transcript"][0]["answerStartedAt"] == to_iso(T0)


def test_revealing_twice_cannot_restart_a_running_clock() -> None:
    session = _session(_turn())
    conversation.reveal_timed_turn(session, _template(), T0)
    assert conversation.reveal_timed_turn(session, _template(), T0 + 60 * SECOND) is False
    assert session["transcript"][0]["answerStartedAt"] == to_iso(T0)


def test_revealing_a_thinking_turn_starts_the_thinking_clock() -> None:
    template = _template()
    template["chatbotTimer"]["includeThinkingPhase"] = True
    session = _session(_turn())

    conversation.reveal_timed_turn(session, template, T0)
    assert session["transcript"][0]["thinkingStartedAt"] == to_iso(T0)
    assert session["transcript"][0].get("answerStartedAt") is None


def test_an_untimed_turn_arms_nothing() -> None:
    session = _session(_turn(turnType="greeting"))
    assert conversation.reveal_timed_turn(session, _template(), T0) is False
    assert "answerStartedAt" not in session["transcript"][0]


def test_a_finished_session_arms_nothing() -> None:
    session = _session(_turn(), status="completed")
    assert conversation.reveal_timed_turn(session, _template(), T0) is False


# ── advancing ─────────────────────────────────────────────────────────────────


def test_a_running_answer_window_does_not_expire_early() -> None:
    session = _session(_turn(answerStartedAt=to_iso(T0)))
    assert conversation.advance_chatbot_timing(session, _template(), T0 + 60 * SECOND) == "none"


def test_an_elapsed_answer_window_signals_expiry() -> None:
    session = _session(_turn(answerStartedAt=to_iso(T0)))
    assert conversation.advance_chatbot_timing(session, _template(), T0 + 121 * SECOND) == "answer_expired"


def test_expiry_signals_rather_than_submitting() -> None:
    """Auto-submitting means writing the draft and generating the next turn, which is the
    route's job — this stays pure."""
    session = _session(_turn(answerStartedAt=to_iso(T0), draft="half an answer"))
    conversation.advance_chatbot_timing(session, _template(), T0 + 200 * SECOND)
    assert session["transcript"][0].get("submittedAt") is None
    assert session["transcript"][0]["draft"] == "half an answer"


def test_thinking_rolls_into_answering_at_the_deadline() -> None:
    """Stamped at the deadline, so a session that went unread does not charge the wait
    against the answer window."""
    template = _template()
    template["chatbotTimer"]["includeThinkingPhase"] = True
    session = _session(_turn(thinkingStartedAt=to_iso(T0)))

    conversation.advance_chatbot_timing(session, template, T0 + 300 * SECOND)
    assert session["transcript"][0]["answerStartedAt"] == to_iso(T0 + 20 * SECOND)


def test_thinking_still_running_holds_the_answer_clock() -> None:
    template = _template()
    template["chatbotTimer"]["includeThinkingPhase"] = True
    session = _session(_turn(thinkingStartedAt=to_iso(T0)))

    assert conversation.advance_chatbot_timing(session, template, T0 + 5 * SECOND) == "none"
    assert session["transcript"][0].get("answerStartedAt") is None


def test_expiry_is_suppressed_when_auto_submit_is_off() -> None:
    template = _template()
    template["chatbotTimer"]["autoSubmitOnExpiry"] = False
    session = _session(_turn(answerStartedAt=to_iso(T0)))
    assert conversation.advance_chatbot_timing(session, template, T0 + 999 * SECOND) == "none"


def test_a_turn_not_yet_presented_never_expires() -> None:
    """Its clock has not started, so there is nothing to run out."""
    session = _session(_turn())
    assert conversation.advance_chatbot_timing(session, _template(), T0 + 9999 * SECOND) == "none"


# ── skipping the thinking phase ───────────────────────────────────────────────


def test_thinking_can_be_skipped_when_allowed() -> None:
    template = _template()
    template["chatbotTimer"]["includeThinkingPhase"] = True
    session = _session(_turn(thinkingStartedAt=to_iso(T0)))

    assert conversation.skip_thinking(session, template) is True
    assert session["transcript"][0].get("answerStartedAt")


def test_skipping_is_refused_once_answering_has_started() -> None:
    """A candidate must not be able to restart their own clock."""
    template = _template()
    template["chatbotTimer"]["includeThinkingPhase"] = True
    session = _session(_turn(thinkingStartedAt=to_iso(T0), answerStartedAt=to_iso(T0 + SECOND)))

    assert conversation.skip_thinking(session, template) is False
    assert session["transcript"][0]["answerStartedAt"] == to_iso(T0 + SECOND)


def test_skipping_is_refused_without_a_thinking_phase() -> None:
    session = _session(_turn())
    assert conversation.skip_thinking(session, _template()) is False


def test_skipping_is_refused_on_a_submitted_turn() -> None:
    template = _template()
    template["chatbotTimer"]["includeThinkingPhase"] = True
    session = _session(_turn(thinkingStartedAt=to_iso(T0), submittedAt=to_iso(T0)))
    assert conversation.skip_thinking(session, template) is False


# ── the current turn ──────────────────────────────────────────────────────────


def test_the_current_turn_is_the_last_unanswered_interviewer_turn() -> None:
    session = _session(
        _turn(id="t1", submittedAt=to_iso(T0)),
        {"id": "a1", "role": "candidate", "content": "answered"},
        _turn(id="t2"),
    )
    assert conversation.current_interviewer_turn(session)["id"] == "t2"


def test_there_is_no_current_turn_once_everything_is_answered() -> None:
    session = _session(_turn(submittedAt=to_iso(T0)))
    assert conversation.current_interviewer_turn(session) is None


# ── the client-safe state ─────────────────────────────────────────────────────


def test_the_state_never_leaks_per_turn_timing_or_drafts() -> None:
    """Raw turns carry `draft`, the clocks and `submittedAt`. Handing those over lets a
    client reconstruct exactly how long the candidate took on each turn — and edit and
    replay it."""
    session = _session(
        _turn(
            id="t1",
            submittedAt=to_iso(T0),
            answerStartedAt=to_iso(T0),
            thinkingStartedAt=to_iso(T0),
            draft="secret draft",
        )
    )
    state = conversation.compute_chatbot_state(session, _template(), T0)

    projected = state["transcript"][0]
    assert set(projected) == {"id", "role", "content", "turnType", "questionIndex", "isFollowUp"}
    assert "secret draft" not in str(state["transcript"])


def test_the_answer_countdown_reflects_elapsed_time() -> None:
    session = _session(_turn(answerStartedAt=to_iso(T0)))
    state = conversation.compute_chatbot_state(session, _template(), T0 + 20 * SECOND)
    assert state["phase"] == "answer"
    assert state["remainingSeconds"] == 100
    assert state["totalPhaseSeconds"] == 120


def test_a_timed_turn_not_yet_presented_has_no_phase_but_announces_a_clock() -> None:
    """So the client knows a countdown is coming and can render the timer chrome."""
    session = _session(_turn())
    state = conversation.compute_chatbot_state(session, _template(), T0)
    assert state["phase"] is None
    assert state["currentTurnTimed"] is True
    assert state["currentTurnId"] == "t1"


def test_an_untimed_turn_reports_no_clock() -> None:
    session = _session(_turn(turnType="greeting"))
    state = conversation.compute_chatbot_state(session, _template(), T0)
    assert state["currentTurnTimed"] is False
    assert state["phase"] is None


def test_the_countdown_never_goes_negative() -> None:
    session = _session(_turn(answerStartedAt=to_iso(T0)))
    state = conversation.compute_chatbot_state(session, _template(), T0 + 9999 * SECOND)
    assert state["remainingSeconds"] == 0


def test_a_finished_session_reports_finished_with_no_current_turn() -> None:
    session = _session(_turn(), status="completed")
    state = conversation.compute_chatbot_state(session, _template(), T0)
    assert state["finished"] is True
    assert state["currentTurnId"] is None
    assert state["phase"] is None


def test_the_draft_is_returned_so_a_reconnect_resumes() -> None:
    session = _session(_turn(answerStartedAt=to_iso(T0), draft="half an answer"))
    assert conversation.compute_chatbot_state(session, _template(), T0)["draft"] == "half an answer"


def test_progress_uses_the_planned_count() -> None:
    """Shown from the first turn, so the candidate knows the length of what they agreed
    to."""
    state = conversation.compute_chatbot_state(_session(_turn()), _template(), T0)
    assert state["progress"] == {"current": 1, "total": 5}


def test_a_stored_planned_count_wins() -> None:
    """An adaptive interview fixes its length when the questions are generated."""
    session = _session(_turn(), plannedQuestionCount=3)
    assert conversation.compute_chatbot_state(session, _template(), T0)["progress"]["total"] == 3


def test_a_fixed_interview_counts_its_question_set() -> None:
    template = _template(questionSource="fixed")
    state = conversation.compute_chatbot_state(
        _session(_turn()), template, T0, fixed_question_count=7
    )
    assert state["progress"]["total"] == 7


def test_an_adaptive_template_awaits_a_resume() -> None:
    state = conversation.compute_chatbot_state(_session(_turn()), _template(), T0)
    assert state["awaitingResume"] is True
    assert conversation.compute_chatbot_state(
        _session(_turn(), resumeText="Ada"), _template(), T0
    )["awaitingResume"] is False


# ── the brevity guard ─────────────────────────────────────────────────────────


def test_a_compound_question_is_flagged() -> None:
    """A candidate cannot answer three questions at once, and it is unbearable read
    aloud."""
    assert conversation.too_long("Tell me about X? And how did you Y? And why Z?")
    assert not conversation.too_long("Tell me about a project you are proud of.")


def test_an_over_long_message_is_flagged() -> None:
    assert conversation.too_long(" ".join(["word"] * 60))
    assert not conversation.too_long(" ".join(["word"] * 50))


def test_trimming_keeps_the_first_askable_question() -> None:
    trimmed = conversation.trim_to_single_question(
        "Nice. Tell me about your work on Kafka? And what about React? And Redis?"
    )
    assert trimmed == "Nice. Tell me about your work on Kafka?"


def test_trimming_with_no_question_mark_is_visibly_incomplete() -> None:
    """Better than a sentence that stops mid-clause and reads as a bug."""
    trimmed = conversation.trim_to_single_question(" ".join(["word"] * 60))
    assert trimmed.endswith("…")
    # 40 words; the ellipsis attaches to the last one rather than standing alone.
    assert len(trimmed.split()) == 40


def test_short_messages_pass_through_untrimmed() -> None:
    assert conversation.trim_to_single_question("Why this role?") == "Why this role?"


# ── punctuation ───────────────────────────────────────────────────────────────


def test_dashes_become_commas() -> None:
    """A heavy dash style is the clearest tell that a machine wrote something, and these
    are read aloud."""
    assert conversation.humanize_punctuation("Tell me — briefly — about Kafka.") == (
        "Tell me, briefly, about Kafka."
    )


def test_word_hyphens_survive() -> None:
    assert conversation.humanize_punctuation("your follow-up work") == "your follow-up work"


def test_a_comma_stranded_before_a_stop_is_removed() -> None:
    assert conversation.humanize_punctuation("You shipped it —.") == "You shipped it."


def test_empty_input_is_safe() -> None:
    assert conversation.humanize_punctuation("") == ""
    assert conversation.humanize_punctuation(None) == ""
