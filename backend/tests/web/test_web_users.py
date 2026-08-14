"""Role resolution and the admin overlay.

The role is the fact three codebases must agree on — the web client, the Flutter
app and this server all read Firestore `users/{uid}.role`. These tests pin the
defaults and the failure behaviour, because getting them wrong either locks
recruiters out or hands a candidate a recruiter's view.
"""

from __future__ import annotations

import asyncio

import pytest

from app.config import Settings
from app.security import AuthedUser
from app.web.services import users


class _Snapshot:
    def __init__(self, data: dict | None) -> None:
        self.exists = data is not None
        self._data = data

    def to_dict(self) -> dict | None:
        return self._data


class _FakeDb:
    """The two calls `users.py` makes, and nothing else."""

    def __init__(self, data: dict | None = None, *, raises: bool = False) -> None:
        self._data = data
        self._raises = raises

    def collection(self, _name: str) -> "_FakeDb":
        return self

    def document(self, _uid: str) -> "_FakeDb":
        return self

    def get(self) -> _Snapshot:
        if self._raises:
            raise RuntimeError("firestore is down")
        return _Snapshot(self._data)


@pytest.fixture
def settings() -> Settings:
    return Settings(admin_emails="boss@talbotiq.com, other@talbotiq.com")


def _patch_db(monkeypatch: pytest.MonkeyPatch, db: _FakeDb) -> None:
    monkeypatch.setattr(users, "get_db", lambda _settings: db)


# ── role ──────────────────────────────────────────────────────────────────────


def test_recruiter_role_is_read_from_the_document(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    _patch_db(monkeypatch, _FakeDb({"role": "recruiter"}))
    assert asyncio.run(users.get_role(settings, "uid-1")) == users.RECRUITER


def test_a_missing_document_is_a_candidate(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    """Least privilege, matching the clients' auth-gate default."""
    _patch_db(monkeypatch, _FakeDb(None))
    assert asyncio.run(users.get_role(settings, "uid-1")) == users.CANDIDATE


def test_an_unrecognised_role_is_a_candidate(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    """The document is client-writable, so anything other than the exact string
    `recruiter` must not be treated as elevated."""
    _patch_db(monkeypatch, _FakeDb({"role": "admin"}))
    assert asyncio.run(users.get_role(settings, "uid-1")) == users.CANDIDATE


def test_an_unreachable_firestore_degrades_instead_of_raising(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    """A broken Firestore must not turn every authenticated request into a 500
    when the safe answer is available."""
    _patch_db(monkeypatch, _FakeDb(raises=True))
    assert asyncio.run(users.get_role(settings, "uid-1")) == users.CANDIDATE


def test_a_blank_uid_never_reaches_firestore(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    def _boom(_settings):
        raise AssertionError("should not query for a blank uid")

    monkeypatch.setattr(users, "get_db", _boom)
    assert asyncio.run(users.get_role(settings, "")) == users.CANDIDATE


# ── display name ──────────────────────────────────────────────────────────────


def test_display_name_prefers_name_then_display_name(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    _patch_db(monkeypatch, _FakeDb({"name": "Ada"}))
    assert asyncio.run(users.get_display_name(settings, "uid-1")) == "Ada"

    _patch_db(monkeypatch, _FakeDb({"displayName": "Grace"}))
    assert asyncio.run(users.get_display_name(settings, "uid-1")) == "Grace"


def test_display_name_is_none_when_absent_or_unreadable(
    monkeypatch: pytest.MonkeyPatch, settings: Settings
) -> None:
    """Best-effort by design — an invite must not fail over a missing profile."""
    _patch_db(monkeypatch, _FakeDb({}))
    assert asyncio.run(users.get_display_name(settings, "uid-1")) is None

    _patch_db(monkeypatch, _FakeDb(raises=True))
    assert asyncio.run(users.get_display_name(settings, "uid-1")) is None


# ── admin overlay ─────────────────────────────────────────────────────────────


def test_admin_requires_both_the_allowlist_and_the_recruiter_role(
    settings: Settings,
) -> None:
    """The overlay widens a recruiter's visibility; it must not promote a
    candidate who happens to be listed."""
    assert users.is_admin(settings, email="boss@talbotiq.com", role="recruiter")
    assert not users.is_admin(settings, email="boss@talbotiq.com", role="candidate")
    assert not users.is_admin(settings, email="nobody@talbotiq.com", role="recruiter")


def test_admin_matching_ignores_case_and_padding(settings: Settings) -> None:
    assert users.is_admin(settings, email="  BOSS@Talbotiq.com ", role="recruiter")


def test_a_blank_allowlist_disables_the_overlay() -> None:
    empty = Settings(admin_emails="")
    assert not users.is_admin(empty, email="boss@talbotiq.com", role="recruiter")


def test_a_missing_email_is_never_an_admin(settings: Settings) -> None:
    assert not users.is_admin(settings, email=None, role="recruiter")
    assert not users.is_admin(settings, email="", role="recruiter")


def test_allowlist_accepts_commas_spaces_and_newlines() -> None:
    parsed = users.admin_emails(Settings(admin_emails="a@x.com, b@x.com\nc@x.com d@x.com"))
    assert parsed == {"a@x.com", "b@x.com", "c@x.com", "d@x.com"}


# ── email verification ────────────────────────────────────────────────────────


def test_email_verified_comes_from_the_token_claims() -> None:
    """Read from the signed token, never a document — a client-writable field
    saying "verified" would mean nothing."""
    verified = AuthedUser(uid="u", email="a@x.com", claims={"email_verified": True})
    unverified = AuthedUser(uid="u", email="a@x.com", claims={"email_verified": False})
    absent = AuthedUser(uid="u", email="a@x.com", claims={})

    assert users.email_verified(verified)
    assert not users.email_verified(unverified)
    assert not users.email_verified(absent)
