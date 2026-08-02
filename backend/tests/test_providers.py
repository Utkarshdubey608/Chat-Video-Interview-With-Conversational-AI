"""Phase 1 foundation: provider readiness, error mapping, and Firebase auth.

No network and no credentials — the HTTP layer is stubbed, and Firebase's
verifier is monkeypatched. What's under test is our own plumbing: that a missing
key becomes a 503, that a vendor 401 never leaks out as a 401, and that the
bearer-token dependency accepts exactly what it should.
"""

from __future__ import annotations

import os

os.environ.setdefault("DRY_RUN", "true")
os.environ.setdefault("API_KEY", "")

import pytest  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.config import Settings  # noqa: E402
from app.main import _register_error_handlers  # noqa: E402
from app.providers import readiness  # noqa: E402
from app.providers.base import (  # noqa: E402
    ProviderClient,
    ProviderNotConfigured,
    UpstreamError,
)


def settings(**overrides) -> Settings:
    """Settings built in isolation from the developer's real backend/.env.

    Without `_env_file=None` these tests would pass or fail depending on which
    keys happen to be configured on the machine running them.
    """
    return Settings(_env_file=None, **overrides)


# --- readiness -------------------------------------------------------------
def test_readiness_reports_only_configured_providers():
    assert readiness(settings(gemini_api_key="AIza-x", tavus_api_key="  ")) == {
        "gemini": True,
        "tavus": False,  # whitespace is not a key
        "deepgram": False,
    }


def test_live_model_name_is_normalised():
    assert settings(gemini_live_model="gemini-x").live_model_name == "models/gemini-x"
    assert settings(gemini_live_model="models/gemini-x").live_model_name == "models/gemini-x"


# --- ProviderClient --------------------------------------------------------
class _Fake(ProviderClient):
    name = "fake"
    env_var = "FAKE_API_KEY"
    base_url = "https://fake.example.com/v1"

    @property
    def api_key(self) -> str:
        return self.settings.gemini_api_key

    def auth_headers(self) -> dict[str, str]:
        return {"x-key": self.api_key}


def test_unconfigured_provider_raises_with_the_env_var_name():
    with pytest.raises(ProviderNotConfigured) as exc:
        _Fake(settings(gemini_api_key="")).require_configured()
    assert "FAKE_API_KEY" in str(exc.value)


def test_url_joins_relative_and_passes_absolute_through():
    client = _Fake(settings(gemini_api_key="k"))
    assert client.url("/things") == "https://fake.example.com/v1/things"
    assert client.url("https://elsewhere.test/x") == "https://elsewhere.test/x"


@pytest.mark.parametrize(
    ("upstream", "expected"),
    [
        (401, 503),  # OUR key is bad — never echo as the caller's 401
        (403, 503),
        (429, 429),  # rate limits are worth passing through
        (400, 400),
        (404, 404),
        (500, 502),  # anything unexpected collapses to a bad-gateway
        (503, 502),
    ],
)
def test_upstream_status_mapping(upstream: int, expected: int):
    assert UpstreamError("fake", upstream, "boom").client_status == expected


# --- error handlers --------------------------------------------------------
def _app_that_raises(exc: Exception) -> TestClient:
    app = FastAPI()
    _register_error_handlers(app)

    @app.get("/boom")
    async def boom():
        raise exc

    return TestClient(app, raise_server_exceptions=False)


def test_not_configured_becomes_503_with_a_fixable_message():
    client = _app_that_raises(ProviderNotConfigured("Tavus", "TAVUS_API_KEY"))
    response = client.get("/boom")
    assert response.status_code == 503
    assert "TAVUS_API_KEY" in response.json()["detail"]


def test_upstream_error_does_not_leak_the_vendor_body():
    secret = "candidate resume text that should not be echoed"
    client = _app_that_raises(UpstreamError("Gemini", 400, secret))
    response = client.get("/boom")
    assert response.status_code == 400
    assert secret not in response.text
    assert response.json()["upstream_status"] == 400


# --- Firebase auth ---------------------------------------------------------
def _auth_client(monkeypatch, *, verify) -> TestClient:
    """An app with one guarded route, and Firebase's verifier stubbed."""
    import app.security as security

    monkeypatch.setattr(security, "ensure_app", lambda _s: None)

    class _FakeAuth:
        @staticmethod
        def verify_id_token(token, check_revoked=False):
            return verify(token)

    monkeypatch.setitem(
        __import__("sys").modules, "firebase_admin", type("m", (), {"auth": _FakeAuth})
    )
    monkeypatch.setitem(__import__("sys").modules, "firebase_admin.auth", _FakeAuth)

    app = FastAPI()
    app.state.settings = settings()

    @app.get("/me")
    async def me(user=security.CurrentUser):
        return {"uid": user.uid, "role": user.role}

    return TestClient(app, raise_server_exceptions=False)


@pytest.mark.parametrize("header", [None, "", "Token abc", "Bearer", "Bearer   "])
def test_malformed_authorization_header_is_401(monkeypatch, header):
    client = _auth_client(monkeypatch, verify=lambda _t: {"uid": "u1"})
    headers = {} if header is None else {"Authorization": header}
    assert client.get("/me", headers=headers).status_code == 401


def test_valid_token_yields_the_uid_and_role(monkeypatch):
    client = _auth_client(
        monkeypatch,
        verify=lambda _t: {"uid": "u1", "email": "a@b.c", "role": "recruiter"},
    )
    response = client.get("/me", headers={"Authorization": "Bearer good"})
    assert response.status_code == 200
    assert response.json() == {"uid": "u1", "role": "recruiter"}


def test_rejected_token_is_401_and_never_echoes_the_token(monkeypatch):
    def _reject(_token):
        raise ValueError("expired")

    client = _auth_client(monkeypatch, verify=_reject)
    response = client.get("/me", headers={"Authorization": "Bearer sup3rs3cret"})
    assert response.status_code == 401
    assert "sup3rs3cret" not in response.text


def test_token_without_uid_is_401(monkeypatch):
    client = _auth_client(monkeypatch, verify=lambda _t: {"email": "a@b.c"})
    assert client.get("/me", headers={"Authorization": "Bearer x"}).status_code == 401


# --- CORS ------------------------------------------------------------------
def test_wildcard_origins_do_not_get_credentialed_access():
    """`*` + allow_credentials makes the middleware echo any Origin back."""
    from starlette.middleware.cors import CORSMiddleware

    from app.main import create_app

    app = create_app()
    app.state.settings = settings(cors_origins="*")
    cors = [m for m in app.user_middleware if m.cls is CORSMiddleware][0]
    assert cors.kwargs["allow_credentials"] is False


def test_explicit_origins_keep_credentialed_access(monkeypatch):
    from starlette.middleware.cors import CORSMiddleware

    import app.main as main

    # main.py does `from app.config import get_settings`, binding the name at
    # import time — patching app.config would have no effect here.
    monkeypatch.setattr(
        main, "get_settings", lambda: settings(cors_origins="https://app.example.com")
    )
    app = main.create_app()

    cors = [m for m in app.user_middleware if m.cls is CORSMiddleware][0]
    assert cors.kwargs["allow_origins"] == ["https://app.example.com"]
    assert cors.kwargs["allow_credentials"] is True
