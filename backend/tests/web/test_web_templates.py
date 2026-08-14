"""Interview templates and question sets.

The template builder is where most of the behaviour lives: which defaults apply, and
which track-dependent sections exist at all. A section present on the wrong track
implies a feature is in play when it is not.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.web.routes.question_sets import normalise_questions
from app.web.routes.templates import build_template
from app.web.store import defaults

NOW = "2026-08-13T12:00:00+00:00"


def _template(**body) -> dict:
    return build_template(body, template_id="t1", now=NOW)


# ── template defaults ─────────────────────────────────────────────────────────


def test_an_empty_request_produces_a_usable_template() -> None:
    template = _template()
    assert template["id"] == "t1"
    assert template["name"] == "Untitled template"
    assert template["track"] == "chat"
    assert template["questionSource"] == "fixed"
    assert template["timing"] == defaults.DEFAULT_TIMING
    assert template["integrity"] == defaults.DEFAULT_INTEGRITY
    assert template["branding"] == defaults.DEFAULT_BRANDING
    assert template["createdAt"] == template["updatedAt"] == NOW


def test_a_partial_section_keeps_the_other_defaults() -> None:
    """A client sending only one timing field must not blank the rest."""
    template = _template(timing={"answerSeconds": 300})
    assert template["timing"]["answerSeconds"] == 300
    assert template["timing"]["prepSeconds"] == defaults.DEFAULT_TIMING["prepSeconds"]
    assert template["timing"]["allowSkipPrep"] is True


def test_the_default_rubric_is_applied_when_absent() -> None:
    assert template_kpi_ids(_template()) == [
        "communication", "relevance", "depth", "structure",
        "problem_solving", "professionalism",
    ]


def test_a_supplied_rubric_wins() -> None:
    custom = {"scoreScale": 10, "kpis": [{"id": "x", "label": "X", "weight": 2, "enabled": True}]}
    assert _template(rubric=custom)["rubric"] == custom


def template_kpi_ids(template: dict) -> list[str]:
    return [k["id"] for k in template["rubric"]["kpis"]]


# ── track-dependent sections ──────────────────────────────────────────────────


def test_a_chat_template_carries_no_conversational_sections() -> None:
    """A voice config on a typed track would imply the voice is used. It is not."""
    template = _template(track="chat")
    for absent in ("voice", "adaptive", "conversationTiming", "mode"):
        assert absent not in template, absent


def test_a_voice_template_gets_a_voice_config_and_conversational_mode() -> None:
    template = _template(track="voice")
    assert template["mode"] == "conversational"
    assert template["voice"] == defaults.default_voice_config()
    # A voice interview is not a chatbot: no per-question chatbot timer.
    assert "chatbotTimer" not in template


def test_a_chatbot_template_gets_the_timer_and_conversation_timing() -> None:
    template = _template(track="chatbot")
    assert template["mode"] == "conversational"
    assert template["conversationTiming"] == defaults.DEFAULT_CONVERSATION_TIMING
    assert template["chatbotTimer"] == defaults.DEFAULT_CHATBOT_TIMER


def test_video_avatar_gets_the_timer_but_not_conversation_timing() -> None:
    template = _template(track="video_avatar")
    assert template["chatbotTimer"] == defaults.DEFAULT_CHATBOT_TIMER
    assert "conversationTiming" not in template


def test_adaptive_config_appears_only_for_a_conversational_adaptive_template() -> None:
    assert "adaptive" in _template(track="chatbot", questionSource="adaptive")
    assert "adaptive" in _template(track="voice", questionSource="adaptive")
    # Fixed questions need no adaptive config...
    assert "adaptive" not in _template(track="chatbot", questionSource="fixed")
    # ...and neither does a typed track, even asking for adaptive.
    assert "adaptive" not in _template(track="chat", questionSource="adaptive")


def test_the_adaptive_config_takes_the_role() -> None:
    template = _template(track="chatbot", questionSource="adaptive", role="Data Scientist")
    assert template["adaptive"]["role"] == "Data Scientist"


def test_an_adaptive_template_with_no_role_gets_a_sensible_default() -> None:
    template = _template(track="chatbot", questionSource="adaptive")
    assert template["adaptive"]["role"] == "Software Engineer"


def test_an_explicit_section_always_wins_over_the_track_default() -> None:
    custom_voice = {"engine": "gemini_live", "voiceId": "Charon", "personaId": "exec_panel"}
    assert _template(track="voice", voice=custom_voice)["voice"] == custom_voice


# ── question normalisation ────────────────────────────────────────────────────


def test_question_order_is_preserved() -> None:
    """The array order IS the saved order — that is what drag-to-reorder relies on."""
    questions = normalise_questions(
        [{"id": "a", "text": "First"}, {"id": "b", "text": "Second"}, {"id": "c", "text": "Third"}]
    )
    assert [q["id"] for q in questions] == ["a", "b", "c"]


def test_existing_question_ids_are_kept() -> None:
    """Renumbering would orphan the answers an in-flight session already recorded."""
    assert normalise_questions([{"id": "keep-me", "text": "Q"}])[0]["id"] == "keep-me"


def test_a_question_with_no_id_is_given_one() -> None:
    generated = normalise_questions([{"text": "Q"}])[0]["id"]
    assert generated and len(generated) > 10


def test_blank_questions_are_dropped() -> None:
    """An empty question is read aloud as silence in the voice and avatar tracks."""
    kept = normalise_questions(
        [{"text": "  "}, {"text": ""}, {"text": "Real"}, {"no_text": 1}]
    )
    assert [q["text"] for q in kept] == ["Real"]


def test_question_text_is_trimmed() -> None:
    assert normalise_questions([{"text": "  padded  "}])[0]["text"] == "padded"


def test_optional_fields_become_none_not_empty_string() -> None:
    question = normalise_questions([{"text": "Q", "category": "", "idealAnswerNotes": ""}])[0]
    assert question["category"] is None
    assert question["idealAnswerNotes"] is None


def test_malformed_input_yields_nothing() -> None:
    for raw in (None, {}, "text", 42, [None], ["string"], [42]):
        assert normalise_questions(raw) == []


# ── routes ────────────────────────────────────────────────────────────────────


def test_templates_round_trip(authed_client: TestClient) -> None:
    created = authed_client.post(
        "/api/web/templates", json={"name": "Backend screen", "track": "voice", "role": "Backend"}
    ).json()
    assert created["track"] == "voice"

    fetched = authed_client.get(f"/api/web/templates/{created['id']}").json()
    assert fetched == created

    listed = authed_client.get("/api/web/templates").json()
    assert [t["id"] for t in listed] == [created["id"]]


def test_a_missing_template_is_a_404(authed_client: TestClient) -> None:
    response = authed_client.get("/api/web/templates/nope")
    assert response.status_code == 404
    assert response.json()["error"] == "Template not found"


def test_update_cannot_rewrite_identity(authed_client: TestClient) -> None:
    """A client echoing a stale or wrong id must not be able to move the record."""
    created = authed_client.post("/api/web/templates", json={"name": "A"}).json()
    updated = authed_client.put(
        f"/api/web/templates/{created['id']}",
        json={"name": "B", "id": "hijacked", "createdAt": "1999-01-01T00:00:00Z"},
    ).json()

    assert updated["id"] == created["id"]
    assert updated["createdAt"] == created["createdAt"]
    assert updated["name"] == "B"
    assert updated["updatedAt"] >= created["updatedAt"]


def test_updating_a_missing_template_is_a_404(authed_client: TestClient) -> None:
    assert authed_client.put("/api/web/templates/nope", json={"name": "x"}).status_code == 404


def test_delete_is_idempotent(authed_client: TestClient) -> None:
    """Express answered 204 whether or not the row existed; a second delete from a
    double-click must not surface as an error."""
    created = authed_client.post("/api/web/templates", json={"name": "A"}).json()
    assert authed_client.delete(f"/api/web/templates/{created['id']}").status_code == 204
    assert authed_client.delete(f"/api/web/templates/{created['id']}").status_code == 204


def test_templates_are_listed_newest_first(authed_client: TestClient, fake_store) -> None:
    for stamp, name in [("2026-01-01T00:00:00Z", "old"), ("2026-06-01T00:00:00Z", "new")]:
        fake_store.templates.docs[name] = {"id": name, "name": name, "updatedAt": stamp}
    assert [t["name"] for t in authed_client.get("/api/web/templates").json()] == ["new", "old"]


def test_templates_require_a_token() -> None:
    from app.main import create_app

    assert TestClient(create_app()).get("/api/web/templates").status_code == 401


def test_question_sets_round_trip(authed_client: TestClient) -> None:
    created = authed_client.post(
        "/api/web/question-sets",
        json={"name": "Screen", "questions": [{"text": "Why us?"}]},
    ).json()
    assert created["name"] == "Screen"
    assert len(created["questions"]) == 1

    listed = authed_client.get("/api/web/question-sets").json()
    assert [s["id"] for s in listed] == [created["id"]]


def test_duplicating_a_set_gives_fresh_question_ids(authed_client: TestClient) -> None:
    """Sharing ids with the original would make per-question answers ambiguous."""
    created = authed_client.post(
        "/api/web/question-sets",
        json={"name": "Screen", "questions": [{"text": "A"}, {"text": "B"}]},
    ).json()
    copy = authed_client.post(f"/api/web/question-sets/{created['id']}/duplicate").json()

    assert copy["name"] == "Screen (copy)"
    assert copy["id"] != created["id"]
    original_ids = {q["id"] for q in created["questions"]}
    assert not original_ids & {q["id"] for q in copy["questions"]}
    assert [q["text"] for q in copy["questions"]] == ["A", "B"]


def test_updating_only_the_name_keeps_the_questions(authed_client: TestClient) -> None:
    """Absent `questions` means "name only" — treating it as empty would wipe the set."""
    created = authed_client.post(
        "/api/web/question-sets", json={"name": "A", "questions": [{"text": "Q"}]}
    ).json()
    updated = authed_client.put(
        f"/api/web/question-sets/{created['id']}", json={"name": "B"}
    ).json()

    assert updated["name"] == "B"
    assert len(updated["questions"]) == 1


def test_an_explicitly_empty_question_array_does_clear_the_set(
    authed_client: TestClient,
) -> None:
    created = authed_client.post(
        "/api/web/question-sets", json={"name": "A", "questions": [{"text": "Q"}]}
    ).json()
    updated = authed_client.put(
        f"/api/web/question-sets/{created['id']}", json={"questions": []}
    ).json()
    assert updated["questions"] == []


def test_question_sets_are_listed_alphabetically(authed_client: TestClient) -> None:
    for name in ["Zebra", "alpha", "Mango"]:
        authed_client.post("/api/web/question-sets", json={"name": name})
    listed = authed_client.get("/api/web/question-sets").json()
    assert [s["name"] for s in listed] == ["alpha", "Mango", "Zebra"]


def test_duplicating_a_missing_set_is_a_404(authed_client: TestClient) -> None:
    assert authed_client.post("/api/web/question-sets/nope/duplicate").status_code == 404
