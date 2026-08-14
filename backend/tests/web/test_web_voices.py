"""The voice catalog and the deliberately-unimplemented preview.

The catalog ids are Google's `prebuiltVoiceConfig.voiceName` values, so a typo
here produces a voice the Live API rejects at interview time rather than at
review time. Hence the exact-set assertion.
"""

from __future__ import annotations

from app.web.schemas import VoiceCatalog
from app.web.store import defaults

# Google's prebuilt native-audio voices, as of the 2026-07 catalog. Changing this
# set is a product decision, not a refactor.
EXPECTED_VOICE_IDS = {
    "Aoede", "Kore", "Leda", "Zephyr", "Callirrhoe", "Erinome", "Despina",
    "Laomedeia", "Charon", "Orus", "Puck", "Fenrir", "Iapetus", "Umbriel",
    "Enceladus", "Algieba",
}


def test_catalog_ids_match_googles_voice_names() -> None:
    assert {v["id"] for v in defaults.voice_catalog()} == EXPECTED_VOICE_IDS


def test_every_entry_carries_the_shared_fields() -> None:
    """`language` and `engine` are filled in once rather than repeated per row, so
    this checks the filling actually happens."""
    for voice in defaults.voice_catalog():
        assert voice["engine"] == "gemini_live"
        assert voice["language"] == "English (multilingual)"
        assert voice["label"]
        assert voice["gender"] in {"male", "female", "neutral"}


def test_catalog_validates_against_the_response_model() -> None:
    """The route returns this through `VoiceCatalog`, so a shape mismatch should
    fail here rather than as a 500 in production."""
    catalog = VoiceCatalog.model_validate(
        {"voices": defaults.voice_catalog(), "personas": defaults.PERSONA_PRESETS}
    )
    assert len(catalog.voices) == len(EXPECTED_VOICE_IDS)
    assert len(catalog.personas) == 4


def test_find_voice_is_exact() -> None:
    """Google's names are case-sensitive; a lenient lookup would send a voice name
    the Live API rejects."""
    assert defaults.find_voice("Aoede") is not None
    assert defaults.find_voice("aoede") is None
    assert defaults.find_voice("") is None
    assert defaults.find_voice("Nonexistent") is None


def test_every_persona_points_at_a_real_voice() -> None:
    """A persona whose default voice is not in the catalog silently falls back at
    interview time, which is the kind of bug nobody notices until a candidate
    hears the wrong interviewer."""
    for persona in defaults.PERSONA_PRESETS:
        assert defaults.find_voice(persona["defaultVoiceId"]) is not None, persona["id"]


def test_default_voice_config_is_internally_consistent() -> None:
    config = defaults.default_voice_config()
    assert defaults.find_voice(config["voiceId"]) is not None
    assert config["personaId"] in {p["id"] for p in defaults.PERSONA_PRESETS}
    assert config["model"] == defaults.default_live_model()


def test_rubric_ids_are_stable_slugs() -> None:
    """`ResultReport.kpiScores` is keyed by these, so a generated id would orphan
    every score already recorded."""
    kpis = defaults.default_rubric()["kpis"]
    ids = [k["id"] for k in kpis]
    assert ids == [
        "communication",
        "relevance",
        "depth",
        "structure",
        "problem_solving",
        "professionalism",
    ]
    assert len(set(ids)) == len(ids)
    assert all(k["enabled"] and k["weight"] == 1 for k in kpis)


def test_default_adaptive_counts_add_up() -> None:
    """`numberOfQuestions` is the real total, so the technical/non-technical split
    must not exceed it — the generator would silently produce a longer interview."""
    adaptive = defaults.default_adaptive()
    assert adaptive["technicalCount"] + adaptive["nonTechnicalCount"] == adaptive["numberOfQuestions"]
    # Follow-ups default off for the same reason.
    assert adaptive["allowFollowUps"] is False


def test_default_adaptive_takes_the_role() -> None:
    assert defaults.default_adaptive("Data Scientist")["role"] == "Data Scientist"
    assert defaults.default_adaptive()["role"] == "Software Engineer"
