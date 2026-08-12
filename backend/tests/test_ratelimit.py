"""Phase 4: per-user rate limiting on the routes that cost money."""

from __future__ import annotations

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.providers import base
from app.ratelimit import Rule, SlidingWindowLimiter
from app.security import AuthedUser, require_firebase_user

USER_A = AuthedUser(uid="user-a", email="a@example.com", claims={})
USER_B = AuthedUser(uid="user-b", email="b@example.com", claims={})

KEYS = dict(
    gemini_api_key="AIza-k",
    tavus_api_key="tv-k",
    deepgram_api_key="dg-k",
)


# --- the window itself ------------------------------------------------------
def test_requests_are_allowed_up_to_the_limit_then_refused():
    limiter = SlidingWindowLimiter()
    rule = Rule(limit=3, window_seconds=60)

    assert [limiter.hit("k", rule) for _ in range(3)] == [None, None, None]
    retry_after = limiter.hit("k", rule)
    assert retry_after is not None and 0 < retry_after <= 60


def test_a_refusal_does_not_extend_the_window():
    """Refusals must not count as hits, or a retrying client locks itself out."""
    limiter = SlidingWindowLimiter()
    rule = Rule(limit=1, window_seconds=60)

    limiter.hit("k", rule)
    first = limiter.hit("k", rule)
    for _ in range(20):
        limiter.hit("k", rule)
    last = limiter.hit("k", rule)

    # The wait shrinks as the original hit ages out; it never grows.
    assert last <= first


def test_keys_are_independent():
    limiter = SlidingWindowLimiter()
    rule = Rule(limit=1, window_seconds=60)
    assert limiter.hit("a", rule) is None
    assert limiter.hit("b", rule) is None
    assert limiter.hit("a", rule) is not None


def test_a_zero_limit_disables_the_rule():
    limiter = SlidingWindowLimiter()
    assert limiter.hit("k", Rule(limit=0, window_seconds=60)) is None


def test_the_window_slides():
    limiter = SlidingWindowLimiter()
    rule = Rule(limit=1, window_seconds=0)  # everything is immediately stale
    assert limiter.hit("k", rule) is None
    assert limiter.hit("k", rule) is None


# --- applied to routes ------------------------------------------------------
@pytest.fixture
def client(monkeypatch):
    app = create_app()
    app.state.settings = Settings(
        _env_file=None, rate_limit_generate=3, rate_limit_media=3, **KEYS
    )
    state: dict = {"user": USER_A, "calls": 0}

    def handler(_request: httpx.Request) -> httpx.Response:
        state["calls"] += 1
        return httpx.Response(200, json={"ok": True})

    monkeypatch.setattr(
        base, "_client", httpx.AsyncClient(transport=httpx.MockTransport(handler))
    )
    app.dependency_overrides[require_firebase_user] = lambda: state["user"]

    test_client = TestClient(app, raise_server_exceptions=False)
    test_client.state = state  # type: ignore[attr-defined]
    return test_client


def generate(client):
    return client.post(
        "/api/gemini/generate", json={"contents": [{"parts": [{"text": "hi"}]}]}
    )


def test_a_burst_is_refused_with_429_and_retry_after(client):
    for _ in range(3):
        assert generate(client).status_code == 200

    response = generate(client)
    assert response.status_code == 429
    assert int(response.headers["Retry-After"]) >= 1
    # The refused request must not reach — or bill — the vendor.
    assert client.state["calls"] == 3


def test_the_limit_is_per_user(client):
    for _ in range(3):
        generate(client)
    assert generate(client).status_code == 429

    client.state["user"] = USER_B
    assert generate(client).status_code == 200, "one user throttled another"


def test_buckets_are_independent(client):
    """A burst of scoring must not stop a candidate starting their interview."""
    for _ in range(3):
        generate(client)
    assert generate(client).status_code == 429

    media = client.post(
        "/api/deepgram/transcribe",
        content=b"audio",
        headers={"Content-Type": "audio/wav"},
    )
    assert media.status_code == 200


def test_read_only_routes_are_not_limited(client):
    """Polling a conversation or job costs nothing and must stay responsive."""
    for _ in range(10):
        assert client.get("/api/tavus/conversations/c1").status_code == 200


def test_limiting_can_be_disabled(client):
    client.app.state.settings = Settings(
        _env_file=None, rate_limit_enabled=False, rate_limit_generate=1, **KEYS
    )
    for _ in range(5):
        assert generate(client).status_code == 200


def test_the_message_never_reveals_another_users_activity(client):
    for _ in range(4):
        generate(client)
    body = client.post(
        "/api/gemini/generate", json={"contents": [{"parts": [{"text": "hi"}]}]}
    ).json()
    assert "user-a" not in str(body)
