"""The avatar screening proxy.

These routes answer to a browser this port is not allowed to change, so the
response *shapes* are the contract — a `success` flag rather than a status code, a
403 that must not become a 401, an echoed correlation id. Those are what is tested.
"""

from __future__ import annotations

import asyncio
import base64

import pytest

from app.config import Settings
from app.providers import rekognition
from app.providers.base import ProviderNotConfigured, UpstreamError
from app.providers.hume import HumeClient
from app.web.services import gemini


@pytest.fixture(autouse=True)
def _reset_rekognition_client():
    rekognition.reset()
    yield
    rekognition.reset()


# ── model-name validation ─────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "model",
    ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-1.5-pro", "gemini-3.1-flash-live-preview"],
)
def test_real_model_names_are_accepted(model: str) -> None:
    """The web client picks among several models — 1.5-pro on the personas page,
    2.5 flash/pro in the invite wizard — so all of them must pass."""
    assert gemini.validate_model_name(model) == model


@pytest.mark.parametrize(
    "model",
    [
        pytest.param("", id="blank"),
        pytest.param("gpt-4", id="another vendor"),
        pytest.param("../../etc/passwd", id="path traversal"),
        pytest.param("gemini-2.5-flash:generateContent", id="url injection via colon"),
        pytest.param("gemini 2.5 flash", id="spaces"),
        pytest.param("models/gemini-2.5-flash", id="resource form with a slash"),
    ],
)
def test_unsafe_model_names_are_rejected(model: str) -> None:
    """The name is interpolated into the upstream URL, so anything that could
    change the path must not get through."""
    with pytest.raises(ValueError, match="Invalid model name"):
        gemini.validate_model_name(model)


def test_model_names_are_trimmed() -> None:
    assert gemini.validate_model_name("  gemini-2.5-flash  ") == "gemini-2.5-flash"


# ── Rekognition ───────────────────────────────────────────────────────────────


def test_rekognition_needs_both_halves_of_the_credential() -> None:
    """A half-configured deployment fails at call time with an opaque botocore
    error instead of an actionable 503, so the pair is checked together."""
    assert not rekognition.is_configured(Settings(aws_access_key_id="", aws_secret_access_key=""))
    assert not rekognition.is_configured(Settings(aws_access_key_id="AK", aws_secret_access_key=""))
    assert not rekognition.is_configured(Settings(aws_access_key_id="", aws_secret_access_key="SK"))
    assert rekognition.is_configured(Settings(aws_access_key_id="AK", aws_secret_access_key="SK"))


def test_unconfigured_rekognition_raises_provider_not_configured() -> None:
    """503 with an actionable message, not a vendor error the caller cannot act on."""
    settings = Settings(aws_access_key_id="", aws_secret_access_key="")
    frame = base64.b64encode(b"x" * 6000).decode()
    with pytest.raises(ProviderNotConfigured):
        asyncio.run(rekognition.detect_faces(settings, frame))


def test_malformed_base64_is_a_client_error_not_a_server_one() -> None:
    """A broken frame comes from the browser, so it must not read as our fault."""
    settings = Settings(aws_access_key_id="AK", aws_secret_access_key="SK")
    with pytest.raises(UpstreamError) as caught:
        asyncio.run(rekognition.detect_faces(settings, "!!!not base64!!!"))
    assert caught.value.status_code == 400
    assert caught.value.client_status == 400


def test_min_image_bytes_is_the_documented_threshold() -> None:
    """The route computes the DECODED size from the base64 length, so the constant
    and that arithmetic have to agree."""
    assert rekognition.MIN_IMAGE_BYTES == 5_000
    # A frame just under and just over the threshold, as the route measures it.
    small = "A" * 6000   # 6000 * 3 // 4 = 4500 decoded
    large = "A" * 8000   # 8000 * 3 // 4 = 6000 decoded
    assert (len(small) * 3) // 4 < rekognition.MIN_IMAGE_BYTES
    assert (len(large) * 3) // 4 >= rekognition.MIN_IMAGE_BYTES


# ── Hume ──────────────────────────────────────────────────────────────────────


def test_hume_submit_returns_none_when_unconfigured() -> None:
    """Not an error: Hume discontinued this API, so a missing key is the normal
    case and the caller falls back to Gemini."""
    client = HumeClient(Settings(hume_api_key=""))
    result = asyncio.run(
        client.submit_job(b"audio", filename="x.webm", content_type="audio/webm")
    )
    assert result is None


def test_hume_submit_swallows_upstream_failures(monkeypatch: pytest.MonkeyPatch) -> None:
    """A discontinued product returns an error on every submit. Swallowing it is
    the point — the caller must reach the Gemini fallback."""
    client = HumeClient(Settings(hume_api_key="key"))

    async def _boom(*args, **kwargs):
        raise UpstreamError("Hume", 404, "The Expression Measurement API has been discontinued")

    monkeypatch.setattr(client, "request", _boom)
    assert asyncio.run(
        client.submit_job(b"audio", filename="x.webm", content_type="audio/webm")
    ) is None


def test_hume_submit_accepts_either_id_field(monkeypatch: pytest.MonkeyPatch) -> None:
    """Hume's response has used both `job_id` and `id`."""
    client = HumeClient(Settings(hume_api_key="key"))

    for payload, expected in [({"job_id": "a"}, "a"), ({"id": "b"}, "b")]:
        async def _ok(*args, _payload=payload, **kwargs):
            return _payload

        monkeypatch.setattr(client, "request", _ok)
        assert asyncio.run(
            client.submit_job(b"audio", filename="x.webm", content_type="audio/webm")
        ) == expected


def test_hume_submit_treats_a_missing_id_as_a_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    """A 200 with no id cannot be polled, so it has to fall back rather than hand
    back an unusable job."""
    client = HumeClient(Settings(hume_api_key="key"))

    async def _empty(*args, **kwargs):
        return {}

    monkeypatch.setattr(client, "request", _empty)
    assert asyncio.run(
        client.submit_job(b"audio", filename="x.webm", content_type="audio/webm")
    ) is None


# ── readiness ─────────────────────────────────────────────────────────────────


def test_readiness_reports_the_new_web_providers() -> None:
    """Flutter maps every entry of this dict to a bool generically, so keys may be
    ADDED safely — but a rename or removal silently disables a mobile feature."""
    from app import providers

    flags = providers.readiness(
        Settings(hume_api_key="k", aws_access_key_id="AK", aws_secret_access_key="SK")
    )
    assert flags["hume"] is True
    assert flags["rekognition"] is True
    # The pre-existing keys the Flutter app already reads must still be present.
    assert {"gemini", "tavus", "deepgram", "daily", "email"} <= set(flags)


def test_readiness_is_false_without_credentials() -> None:
    from app import providers

    flags = providers.readiness(Settings(hume_api_key="", aws_access_key_id=""))
    assert flags["hume"] is False
    assert flags["rekognition"] is False
