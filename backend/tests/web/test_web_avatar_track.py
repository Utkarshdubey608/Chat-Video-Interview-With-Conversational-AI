"""The video-avatar track.

Nobody tells the server which question the avatar is asking — utterances arrive as plain
text from live captions and have to be matched back against the planned script. Getting
that wrong decides which answer is scored against which question, so most of this file
is that matching.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.security import AuthedUser
from app.web.services import avatar_transcript, tavus_candidate
from app.web.shared import speech

CANDIDATE = AuthedUser(uid="uid-cand", email="ada@example.test", claims={})

QUESTIONS = [
    "Tell me about a project you are proud of and your contribution to it.",
    "How do you handle disagreement with a teammate about a technical decision?",
    "Where do you want to grow over the next couple of years?",
]


def _session(**overrides) -> dict:
    return {
        "id": "s1",
        "templateId": "t1",
        "recruiterId": "uid-recruiter",
        "track": "video_avatar",
        "status": "in_progress",
        "candidate": {"name": "Ada", "email": "ada@example.test"},
        "questions": [{"id": f"q{i}", "text": text} for i, text in enumerate(QUESTIONS)],
        "currentIndex": 0,
        "transcript": [],
        **overrides,
    }


# ── matching an utterance to a question ───────────────────────────────────────


def test_an_exact_question_matches() -> None:
    assert avatar_transcript.match_question_index(_session(), QUESTIONS[1]) == 1


def test_a_question_wrapped_in_a_lead_in_matches() -> None:
    """The avatar rarely reads a question bare — it introduces it first."""
    spoken = f"Great, thank you for that. So, {QUESTIONS[0]}"
    assert avatar_transcript.match_question_index(_session(), spoken) == 0


def test_a_clipped_caption_still_matches() -> None:
    """Captions sometimes lose the start of an utterance."""
    clipped = QUESTIONS[2][6:]
    assert avatar_transcript.match_question_index(_session(), clipped) == 2


def test_punctuation_and_case_do_not_matter() -> None:
    spoken = QUESTIONS[1].upper().replace("?", "").replace(",", "")
    assert avatar_transcript.match_question_index(_session(), spoken) == 1


def test_unrelated_speech_matches_nothing() -> None:
    """A wrong match files an answer under the wrong question; a missed one only costs an
    acknowledgment label. The bar is set accordingly."""
    for text in [
        "That is a really thoughtful answer, thank you.",
        "Sorry, could you say that again?",
        "Let me just check my notes for a moment here.",
    ]:
        assert avatar_transcript.match_question_index(_session(), text) is None


def test_a_short_utterance_is_never_matched() -> None:
    """"Yes", "mm-hm" and fragments carry too little to match against."""
    for text in ["Yes", "Mm-hm", "Sure", ""]:
        assert avatar_transcript.match_question_index(_session(), text) is None


def test_a_tie_prefers_a_question_not_yet_asked() -> None:
    """The avatar is instructed to work through the script in order."""
    session = _session(
        questions=[{"id": "a", "text": "Tell me about your background"},
                   {"id": "b", "text": "Tell me about your background"}],
        transcript=[{"turnType": "question", "questionIndex": 0}],
    )
    assert avatar_transcript.match_question_index(session, "Tell me about your background") == 1


def test_a_session_with_no_questions_matches_nothing() -> None:
    assert avatar_transcript.match_question_index(_session(questions=[]), QUESTIONS[0]) is None


# ── appending utterances ──────────────────────────────────────────────────────


def test_a_recognised_question_becomes_a_question_turn() -> None:
    session = _session()
    assert avatar_transcript.append_utterance(session, "interviewer", QUESTIONS[0]) is True

    turn = session["transcript"][0]
    assert turn["turnType"] == "question"
    assert turn["questionIndex"] == 0
    assert session["currentIndex"] == 0


def test_other_interviewer_speech_becomes_an_acknowledgment() -> None:
    """Never scored, never times anything."""
    session = _session()
    avatar_transcript.append_utterance(session, "interviewer", "That's a great example, thank you.")

    turn = session["transcript"][0]
    assert turn["turnType"] == "acknowledgment"
    assert "questionIndex" not in turn


def test_a_repeated_question_does_not_create_a_second_question_turn() -> None:
    """The avatar repeating itself because the candidate did not hear must not show the
    question twice in the report."""
    session = _session()
    avatar_transcript.append_utterance(session, "interviewer", QUESTIONS[0])
    avatar_transcript.append_utterance(session, "interviewer", QUESTIONS[0])

    kinds = [t["turnType"] for t in session["transcript"]]
    assert kinds == ["question", "acknowledgment"]
    assert avatar_transcript.questions_asked(session) == 1


def test_the_cursor_follows_the_question_being_asked() -> None:
    session = _session()
    avatar_transcript.append_utterance(session, "interviewer", QUESTIONS[2])
    assert session["currentIndex"] == 2


def test_candidate_speech_is_bucketed_under_the_current_question() -> None:
    session = _session()
    avatar_transcript.append_utterance(session, "interviewer", QUESTIONS[1])
    avatar_transcript.append_utterance(session, "candidate", "I talk it through with them.")

    answer = session["transcript"][-1]
    assert answer["role"] == "candidate"
    assert answer["questionIndex"] == 1


def test_greeting_chatter_is_kept_but_not_bucketed() -> None:
    """"Yes, I'm ready" is not an answer to question one."""
    session = _session()
    avatar_transcript.append_utterance(session, "candidate", "Yes, I'm ready to begin.")

    turn = session["transcript"][0]
    assert turn["role"] == "candidate"
    assert "questionIndex" not in turn


def test_empty_utterances_are_dropped() -> None:
    session = _session()
    assert avatar_transcript.append_utterance(session, "candidate", "   ") is False
    assert session["transcript"] == []


def test_a_runaway_client_cannot_grow_the_document_without_bound() -> None:
    session = _session(transcript=[{"role": "candidate", "content": "x"}] * avatar_transcript.MAX_TURNS)
    assert avatar_transcript.append_utterance(session, "candidate", "one more") is False


def test_questions_asked_counts_distinct_questions() -> None:
    session = _session()
    for text in (QUESTIONS[0], "Thanks!", QUESTIONS[1], QUESTIONS[1]):
        avatar_transcript.append_utterance(session, "interviewer", text)
    assert avatar_transcript.questions_asked(session) == 2


# ── the Tavus payload ─────────────────────────────────────────────────────────


def _config(**overrides) -> dict:
    return {"replicaId": "r1", "aiName": "Alex", **overrides}


def test_the_payload_carries_the_script_and_the_replica() -> None:
    payload = tavus_candidate.build_payload(
        _config(), candidate_name="Ada", questions=QUESTIONS
    )
    assert payload["replica_id"] == "r1"
    assert "Ada" in payload["conversation_name"]
    for question in QUESTIONS:
        assert question.rstrip("?") in payload["conversational_context"]


def test_transcription_is_always_on() -> None:
    """The candidate's speech becomes the only record this track has to score. Without it
    there is nothing to evaluate."""
    payload = tavus_candidate.build_payload(_config(), candidate_name="Ada", questions=QUESTIONS)
    assert payload["properties"]["enable_transcription"] is True


def test_pipeline_mode_is_never_sent() -> None:
    """Tavus rejects it as an unknown field — that 400 is what broke the old client-side
    path."""
    payload = tavus_candidate.build_payload(_config(), candidate_name="Ada", questions=QUESTIONS)
    assert "pipeline_mode" not in payload["properties"]
    assert "pipeline_mode" not in str(payload)


def test_the_call_duration_is_bounded() -> None:
    short = tavus_candidate.build_payload(
        _config(maxCallDuration=10), candidate_name="Ada", questions=QUESTIONS
    )
    assert short["properties"]["max_call_duration"] == tavus_candidate.DEFAULT_CALL_SECONDS

    valid = tavus_candidate.build_payload(
        _config(maxCallDuration=900), candidate_name="Ada", questions=QUESTIONS
    )
    assert valid["properties"]["max_call_duration"] == 900


def test_the_default_language_is_omitted() -> None:
    """Sending `language: "English"` behaves differently from omitting it."""
    default = tavus_candidate.build_payload(
        _config(language="English"), candidate_name="Ada", questions=QUESTIONS
    )
    assert "language" not in default["properties"]

    spanish = tavus_candidate.build_payload(
        _config(language="Spanish"), candidate_name="Ada", questions=QUESTIONS
    )
    assert spanish["properties"]["language"] == "Spanish"


def test_optional_fields_are_omitted_rather_than_null() -> None:
    payload = tavus_candidate.build_payload(_config(), candidate_name="Ada", questions=QUESTIONS)
    assert "persona_id" not in payload
    assert "callback_url" not in payload
    assert "enable_recording" not in payload["properties"]


def test_a_nameless_candidate_gets_a_placeholder_in_the_conversation_name() -> None:
    payload = tavus_candidate.build_payload(_config(), candidate_name="", questions=QUESTIONS)
    assert payload["conversation_name"].endswith("Candidate")


# ── the spoken context ────────────────────────────────────────────────────────


def test_the_context_forbids_inventing_questions() -> None:
    """An avatar that improvises asks different questions of different candidates, which
    makes the scores incomparable."""
    context = speech.avatar_interview_context(questions=QUESTIONS, candidate_name="Ada")
    assert "Do NOT invent, add, skip, reorder, or rephrase" in context
    assert "never ask follow-ups that are not in the list" in context


def test_the_resume_is_background_not_a_question_source() -> None:
    context = speech.avatar_interview_context(
        questions=QUESTIONS, resume_text="Ada shipped a Kafka pipeline."
    )
    assert "Kafka" in context
    assert "NEVER to add, change, or skip scripted questions" in context


def test_questions_are_stripped_for_speech() -> None:
    """Markdown read aloud becomes noise."""
    context = speech.avatar_interview_context(questions=["**Tell me** about `Kafka`"])
    assert "**" not in context
    assert "`" not in context
    assert "Tell me about Kafka" in context


def test_a_recruiters_greeting_wins() -> None:
    assert speech.avatar_greeting_text(custom="Hi there, shall we start?") == (
        "Hi there, shall we start?"
    )


def test_the_default_greeting_is_time_aware_and_named() -> None:
    greeting = speech.avatar_greeting_text(candidate_name="Ada", time_of_day="morning")
    assert greeting.startswith("Good morning Ada,")
    assert "ready to begin" in greeting


def test_strip_for_speech_removes_list_markers_and_dashes() -> None:
    assert speech.strip_for_speech("1. Tell me — briefly — about X") == "Tell me, briefly, about X"


# ── the routes ────────────────────────────────────────────────────────────────


@pytest.fixture
def avatar_session(fake_store):
    fake_store.templates.docs["t1"] = {
        "id": "t1",
        "name": "Avatar screen",
        "track": "video_avatar",
        "questionSource": "fixed",
        "timing": {"prepSeconds": 30, "answerSeconds": 120},
        "rubric": {"kpis": []},
        "integrity": {"logEvents": True},
        "branding": {},
    }
    fake_store.sessions.docs["s1"] = _session()
    return fake_store


def _client(user: AuthedUser = CANDIDATE) -> TestClient:
    from app.main import create_app
    from app.security import require_firebase_user
    from app.web.deps import web_user_from_query

    app = create_app()
    app.dependency_overrides[require_firebase_user] = lambda: user
    app.dependency_overrides[web_user_from_query] = lambda: user
    return TestClient(app)


def test_avatar_routes_reject_another_track(avatar_session) -> None:
    avatar_session.sessions.docs["s1"]["track"] = "chat"
    client = _client()
    for path in ("start", "transcript", "complete"):
        response = client.post(f"/api/web/sessions/s1/avatar/{path}", json={})
        assert response.status_code == 400
        assert "does not use the video avatar" in response.json()["error"]


def test_starting_without_a_configured_avatar_says_so(avatar_session) -> None:
    response = _client().post("/api/web/sessions/s1/avatar/start", json={})
    assert response.status_code == 400
    assert "Setup page" in response.json()["error"]


def test_a_live_utterance_is_recorded(avatar_session) -> None:
    body = _client().post(
        "/api/web/sessions/s1/avatar/transcript",
        json={"role": "interviewer", "text": QUESTIONS[0]},
    ).json()

    assert body == {"ok": True, "asked": 1, "total": 3}
    assert avatar_session.sessions.docs["s1"]["transcript"][0]["turnType"] == "question"


def test_a_late_utterance_after_completion_is_still_accepted(avatar_session) -> None:
    """Captions lag, so the last answer often lands after the call ends — dropping it
    would lose the thing that makes the interview scoreable."""
    avatar_session.sessions.docs["s1"]["status"] = "completed"
    body = _client().post(
        "/api/web/sessions/s1/avatar/transcript",
        json={"role": "candidate", "text": "One last thought about that."},
    ).json()
    assert body["ok"] is True


def test_a_malformed_utterance_is_refused(avatar_session) -> None:
    client = _client()
    for payload in ({"role": "narrator", "text": "x"}, {"role": "candidate"}, {}):
        assert client.post("/api/web/sessions/s1/avatar/transcript", json=payload).json() == {
            "ok": False
        }


def test_completing_marks_the_session_and_reports_coverage(avatar_session) -> None:
    client = _client()
    client.post(
        "/api/web/sessions/s1/avatar/transcript",
        json={"role": "interviewer", "text": QUESTIONS[0]},
    )
    client.post(
        "/api/web/sessions/s1/avatar/transcript",
        json={"role": "candidate", "text": "I built a parser and shipped it."},
    )

    body = client.post("/api/web/sessions/s1/avatar/complete").json()

    assert body == {"ok": True, "hasAnswers": True, "asked": 1, "total": 3}
    assert avatar_session.sessions.docs["s1"]["status"] == "completed"


def test_a_placeholder_report_is_discarded_when_real_answers_arrive(avatar_session) -> None:
    """"Not evaluated" says nothing was captured. A late caption proves otherwise, so the
    placeholder must not stay next to a transcript full of answers."""
    avatar_session.sessions.docs["s1"]["status"] = "completed"
    avatar_session.reports.docs["s1"] = {"sessionId": "s1", "notEvaluated": True, "overallScore": 0}

    client = _client()
    client.post(
        "/api/web/sessions/s1/avatar/transcript",
        json={"role": "interviewer", "text": QUESTIONS[0]},
    )
    client.post(
        "/api/web/sessions/s1/avatar/transcript",
        json={"role": "candidate", "text": "Here is my real answer to that question."},
    )

    assert "s1" not in avatar_session.reports.docs
