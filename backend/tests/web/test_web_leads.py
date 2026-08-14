"""`POST /api/web/leads` — the one public route on this surface.

Public means the validation IS the security boundary, so the bounds are tested
rather than assumed.
"""

from __future__ import annotations

import pytest

from app.web.routes.leads import DEFAULT_SOURCE, build_lead
from app.web.schemas import LeadCreate

NOW = "2026-08-13T12:00:00+00:00"


def _lead(**overrides) -> LeadCreate:
    return LeadCreate.model_validate(
        {
            "firstName": "Ada",
            "lastName": "Lovelace",
            "email": "ada@example.com",
            "hiresPerYear": "10-50",
            **overrides,
        }
    )


def test_build_lead_normalises_the_email() -> None:
    """The email is what a human searches on later, so case must not split rows."""
    lead = build_lead(_lead(email="Ada.Lovelace@Example.COM"), NOW)
    assert lead["email"] == "ada.lovelace@example.com"


def test_build_lead_trims_surrounding_whitespace() -> None:
    lead = build_lead(_lead(firstName="  Ada  ", hiresPerYear=" 10-50 "), NOW)
    assert lead["firstName"] == "Ada"
    assert lead["hiresPerYear"] == "10-50"


def test_source_defaults_when_absent_or_blank() -> None:
    """A lead with no provenance is indistinguishable from a bug in the page that
    submitted it, so blank falls back rather than being stored empty."""
    assert build_lead(_lead(), NOW)["source"] == DEFAULT_SOURCE
    assert build_lead(_lead(source="   "), NOW)["source"] == DEFAULT_SOURCE
    assert build_lead(_lead(source="partner-x"), NOW)["source"] == "partner-x"


def test_created_at_is_recorded() -> None:
    assert build_lead(_lead(), NOW)["createdAt"] == NOW


def test_no_id_is_invented() -> None:
    """Nothing looks a lead up by id, so Firestore generates one on `add` rather
    than this code minting a key only the write would ever use."""
    assert "id" not in build_lead(_lead(), NOW)


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({"email": "not-an-email"}, id="malformed email"),
        pytest.param({"firstName": ""}, id="blank first name"),
        pytest.param({"lastName": ""}, id="blank last name"),
        pytest.param({"hiresPerYear": ""}, id="blank hires per year"),
        pytest.param({"firstName": "x" * 121}, id="over-long first name"),
        pytest.param({"hiresPerYear": "x" * 121}, id="over-long hires per year"),
        pytest.param({"source": "x" * 121}, id="over-long source"),
    ],
)
def test_invalid_submissions_are_rejected(payload: dict) -> None:
    """Unauthenticated endpoint: every field is bounded, so an oversized or
    malformed submission never reaches storage."""
    with pytest.raises(Exception):
        _lead(**payload)
