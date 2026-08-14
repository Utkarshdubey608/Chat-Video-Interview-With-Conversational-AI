"""Invite-email templates — the one genuinely owner-scoped model in this surface.

These carry a verified sender address and the wording that goes out under a
recruiter's name, so the isolation tests are the point of this file.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.security import AuthedUser
from app.web.routes.invite_email_templates import normalise, parse_kind
from app.web.shared import invite_email

OTHER_RECRUITER = AuthedUser(
    uid="uid-someone-else", email="other@talbotiq.com", claims={"email_verified": True}
)


# ── kind parsing ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize("kind", ["invite", "advance", "selected", "rejection"])
def test_known_kinds_pass_through(kind: str) -> None:
    assert parse_kind(kind) == kind


def test_an_unknown_kind_falls_back_to_invite() -> None:
    """The kind is a query parameter — a stale client should get the invite list, not
    an error page."""
    assert parse_kind("nonsense") == "invite"
    assert parse_kind(None) == "invite"
    assert parse_kind("") == "invite"


# ── normalisation ─────────────────────────────────────────────────────────────


def test_an_empty_body_becomes_the_kind_default() -> None:
    """A partial request must not produce a template that renders a blank email."""
    result = normalise({})
    seed = invite_email.default_template_for("invite")
    assert result["name"] == seed["name"]
    assert result["subject"] == seed["subject"]
    assert result["bodyHtml"] == seed["bodyHtml"]


def test_the_fallback_kind_is_used_when_the_body_names_none() -> None:
    result = normalise({}, fallback_kind="advance")
    assert result["kind"] == "advance"
    assert "{{round_name}}" in result["subject"]


def test_supplied_fields_win() -> None:
    result = normalise({"name": "Mine", "subject": "S {{role}}", "bodyHtml": "<p>B</p>"})
    assert result["name"] == "Mine"
    assert result["subject"] == "S {{role}}"
    assert result["bodyHtml"] == "<p>B</p>"


def test_a_blank_name_falls_back_rather_than_saving_empty() -> None:
    assert normalise({"name": "   "})["name"] == invite_email.default_template_for("invite")["name"]


def test_an_empty_subject_is_respected_but_a_non_string_is_not() -> None:
    """An empty subject is a choice; a number is a client bug."""
    assert normalise({"subject": ""})["subject"] == ""
    assert normalise({"subject": 42})["subject"] == invite_email.default_template_for("invite")["subject"]


def test_identity_fields_are_never_read_from_the_body() -> None:
    """This is what stops a client claiming another recruiter's template."""
    result = normalise(
        {"id": "hijack", "recruiterId": "uid-victim", "createdAt": "1999-01-01"}
    )
    assert "id" not in result
    assert "recruiterId" not in result
    assert "createdAt" not in result


def test_a_blank_reply_to_becomes_empty_string() -> None:
    assert normalise({"sender": {"replyTo": ""}})["sender"]["replyTo"] == ""
    assert normalise({"sender": {"replyTo": "a@x.test"}})["sender"]["replyTo"] == "a@x.test"


def test_a_missing_logo_is_none_not_empty_string() -> None:
    assert normalise({"branding": {}})["branding"]["logoUrl"] is None
    assert normalise({"branding": {"logoUrl": ""}})["branding"]["logoUrl"] is None


def test_a_non_dict_section_is_ignored_rather_than_crashing() -> None:
    result = normalise({"sender": "nope", "cta": 42, "branding": None})
    seed = invite_email.default_template_for("invite")
    assert result["sender"]["fromName"] == seed["sender"]["fromName"]
    assert result["cta"]["color"] == seed["cta"]["color"]


# ── ownership ─────────────────────────────────────────────────────────────────


def test_the_owner_is_stamped_from_the_token(authed_client: TestClient) -> None:
    created = authed_client.post(
        "/api/web/invite-email-templates",
        json={"name": "Mine", "recruiterId": "uid-victim"},
    ).json()
    assert created["recruiterId"] == "uid-recruiter"


def test_another_recruiters_template_is_a_404_not_a_403(
    authed_client: TestClient, fake_store
) -> None:
    """A 403 confirms the id exists, which is enough to enumerate someone else's
    templates."""
    fake_store.invite_email_templates.docs["theirs"] = {
        "id": "theirs",
        "recruiterId": OTHER_RECRUITER.uid,
        "name": "Theirs",
        **invite_email.default_template_for("invite"),
    }

    for method, path in [
        ("GET", "/api/web/invite-email-templates/theirs"),
        ("PUT", "/api/web/invite-email-templates/theirs"),
        ("POST", "/api/web/invite-email-templates/theirs/duplicate"),
        ("DELETE", "/api/web/invite-email-templates/theirs"),
    ]:
        response = authed_client.request(method, path, json={"name": "hijacked"})
        assert response.status_code == 404, f"{method} {path}"
        assert response.json()["error"] == "Invite email template not found"


def test_a_cross_owner_delete_leaves_the_record_alone(
    authed_client: TestClient, fake_store
) -> None:
    fake_store.invite_email_templates.docs["theirs"] = {
        "id": "theirs",
        "recruiterId": OTHER_RECRUITER.uid,
        **invite_email.default_template_for("invite"),
    }
    authed_client.delete("/api/web/invite-email-templates/theirs")
    assert "theirs" in fake_store.invite_email_templates.docs


def test_the_list_shows_only_this_recruiters_templates(
    authed_client: TestClient, fake_store
) -> None:
    for owner, key in [("uid-recruiter", "mine"), (OTHER_RECRUITER.uid, "theirs")]:
        fake_store.invite_email_templates.docs[key] = {
            "id": key,
            "recruiterId": owner,
            "name": key,
            **{k: v for k, v in invite_email.default_template_for("invite").items() if k != "name"},
        }

    listed = authed_client.get("/api/web/invite-email-templates").json()
    assert [t["id"] for t in listed] == ["mine"]


def test_an_update_cannot_reassign_the_owner(authed_client: TestClient) -> None:
    created = authed_client.post("/api/web/invite-email-templates", json={"name": "A"}).json()
    updated = authed_client.put(
        f"/api/web/invite-email-templates/{created['id']}",
        json={"name": "B", "recruiterId": "uid-victim", "id": "hijack"},
    ).json()
    assert updated["recruiterId"] == "uid-recruiter"
    assert updated["id"] == created["id"]


# ── seeding + listing ─────────────────────────────────────────────────────────


def test_a_recruiter_with_none_gets_a_seeded_default(
    authed_client: TestClient, fake_store
) -> None:
    """An empty picker at the moment of sending, with nothing to explain what to do,
    is worse than a sendable starting point."""
    listed = authed_client.get("/api/web/invite-email-templates").json()
    assert len(listed) == 1
    assert listed[0]["isDefault"] is True
    assert listed[0]["recruiterId"] == "uid-recruiter"
    # And it persisted, so the next call does not seed a second one.
    assert len(fake_store.invite_email_templates.docs) == 1
    assert len(authed_client.get("/api/web/invite-email-templates").json()) == 1


def test_the_seeded_default_is_sendable(authed_client: TestClient) -> None:
    seeded = authed_client.get("/api/web/invite-email-templates").json()[0]
    result = invite_email.validate_locked_tokens(
        seeded["subject"], seeded["bodyHtml"], invite_email.kind_of(seeded)
    )
    assert result["ok"], result["missing"]


@pytest.mark.parametrize("kind", ["invite", "advance", "selected", "rejection"])
def test_each_kind_seeds_its_own_default(authed_client: TestClient, kind: str) -> None:
    listed = authed_client.get(
        "/api/web/invite-email-templates", params={"kind": kind}
    ).json()
    assert len(listed) == 1
    assert invite_email.kind_of(listed[0]) == kind


def test_the_list_is_filtered_by_kind(authed_client: TestClient) -> None:
    authed_client.get("/api/web/invite-email-templates", params={"kind": "invite"})
    authed_client.get("/api/web/invite-email-templates", params={"kind": "advance"})

    invites = authed_client.get(
        "/api/web/invite-email-templates", params={"kind": "invite"}
    ).json()
    assert all(invite_email.kind_of(t) == "invite" for t in invites)
    assert len(invites) == 1


def test_a_template_with_no_kind_field_lists_as_an_invite(
    authed_client: TestClient, fake_store
) -> None:
    """Templates saved before kinds existed have no `kind`."""
    legacy = {k: v for k, v in invite_email.default_template_for("invite").items() if k != "kind"}
    fake_store.invite_email_templates.docs["legacy"] = {
        "id": "legacy",
        "recruiterId": "uid-recruiter",
        **legacy,
    }
    listed = authed_client.get("/api/web/invite-email-templates").json()
    assert [t["id"] for t in listed] == ["legacy"]


def test_defaults_sort_before_others(authed_client: TestClient, fake_store) -> None:
    seed = invite_email.default_template_for("invite")
    for key, name, is_default in [("a", "Aaa", False), ("z", "Zzz", True)]:
        fake_store.invite_email_templates.docs[key] = {
            **seed,
            "id": key,
            "recruiterId": "uid-recruiter",
            "name": name,
            "isDefault": is_default,
        }
    listed = authed_client.get("/api/web/invite-email-templates").json()
    assert [t["name"] for t in listed] == ["Zzz", "Aaa"]


# ── duplicate ─────────────────────────────────────────────────────────────────


def test_a_copy_is_never_a_default(authed_client: TestClient) -> None:
    """Two defaults of one kind would make which template sends an arbitrary choice."""
    original = authed_client.get("/api/web/invite-email-templates").json()[0]
    assert original["isDefault"] is True

    copy = authed_client.post(
        f"/api/web/invite-email-templates/{original['id']}/duplicate"
    ).json()
    assert copy["isDefault"] is False
    assert copy["name"] == f"{original['name']} (copy)"
    assert copy["id"] != original["id"]


def test_templates_require_a_token() -> None:
    assert TestClient(create_app()).get("/api/web/invite-email-templates").status_code == 401
