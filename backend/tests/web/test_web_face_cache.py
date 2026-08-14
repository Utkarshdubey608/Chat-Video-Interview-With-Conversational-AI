"""The replica-preview cache.

The host allowlist is a security boundary, not a convenience: without it an
authenticated caller could use this endpoint to fetch arbitrary URLs from inside
the network and have the body handed back. Most of this file is that boundary.
"""

from __future__ import annotations

import pathlib

import pytest

from app.config import Settings
from app.web.routes import face_cache


@pytest.fixture
def settings() -> Settings:
    return Settings()


# ── host allowlist ────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "host",
    [
        "tavus.io",
        "cdn.replica.tavus.io",
        "tavusapi.com",
        "tavus.video",
        "d1abc.cloudfront.net",
        "s3.eu-west-1.amazonaws.com",
    ],
)
def test_tavus_and_its_cdns_are_allowed(settings: Settings, host: str) -> None:
    assert face_cache.is_allowed(settings, host)


@pytest.mark.parametrize(
    "host",
    [
        pytest.param("nottavus.io", id="suffix without a dot boundary"),
        pytest.param("tavus.io.evil.com", id="allowed host as a prefix"),
        pytest.param("evil.com", id="unrelated"),
        pytest.param("localhost", id="loopback"),
        pytest.param("169.254.169.254", id="cloud metadata endpoint"),
        pytest.param("", id="blank"),
    ],
)
def test_everything_else_is_refused(settings: Settings, host: str) -> None:
    assert not face_cache.is_allowed(settings, host)


def test_the_dot_boundary_is_what_stops_prefix_matching(settings: Settings) -> None:
    """A bare endswith("tavus.io") would accept an attacker's `nottavus.io`."""
    assert face_cache.is_allowed(settings, "a.tavus.io")
    assert not face_cache.is_allowed(settings, "nottavus.io")


def test_matching_is_case_insensitive(settings: Settings) -> None:
    assert face_cache.is_allowed(settings, "CDN.Replica.Tavus.IO")


def test_extra_hosts_can_be_configured() -> None:
    """Comma- or space-separated, matching the Express env var's behaviour."""
    settings = Settings(face_cache_hosts="my-cdn.example.com, other.example.net")
    assert face_cache.is_allowed(settings, "my-cdn.example.com")
    assert face_cache.is_allowed(settings, "sub.other.example.net")
    assert not face_cache.is_allowed(settings, "third.example.org")

    spaced = Settings(face_cache_hosts="a.com b.com")
    assert face_cache.is_allowed(spaced, "a.com")
    assert face_cache.is_allowed(spaced, "b.com")


def test_a_blank_allowlist_still_keeps_the_defaults() -> None:
    assert face_cache.allowed_hosts(Settings(face_cache_hosts="")) == face_cache.DEFAULT_HOSTS


# ── cache paths ───────────────────────────────────────────────────────────────


def test_nothing_is_written_to_the_local_filesystem() -> None:
    """Cached previews live in Firebase Storage. A container's disk is ephemeral and
    per-worker, so a disk cache would be lost on every deploy and duplicated across
    workers."""
    source = (
        pathlib.Path(face_cache.__file__).read_text()
    )
    for forbidden in ("write_bytes", "write_text", "open(", "mkdir", "NamedTemporary"):
        assert forbidden not in source, forbidden


def test_the_object_path_is_a_hash_not_the_url() -> None:
    """A CDN path could contain `..` or a separator and land the object somewhere
    unintended, so no part of the URL reaches the path."""
    path = face_cache.object_path("https://cdn.tavus.io/../../etc/passwd")
    assert path.startswith(f"{face_cache.OBJECT_PREFIX}/")
    assert path.endswith(".mp4")
    assert ".." not in path
    assert "passwd" not in path
    assert path.count("/") == 1


def test_the_same_url_maps_to_the_same_object() -> None:
    url = "https://cdn.replica.tavus.io/abc.mp4"
    assert face_cache.object_path(url) == face_cache.object_path(url)
    assert face_cache.download_token(url) == face_cache.download_token(url)


def test_different_urls_map_to_different_objects() -> None:
    a = "https://cdn.replica.tavus.io/a.mp4"
    b = "https://cdn.replica.tavus.io/b.mp4"
    assert face_cache.object_path(a) != face_cache.object_path(b)
    assert face_cache.download_token(a) != face_cache.download_token(b)


def test_the_size_cap_is_generous_but_bounded() -> None:
    """Some Tavus stock previews exceed 40 MB, so the cap is high — but a mistaken
    URL must not be able to fill the drive."""
    assert 40 * 1024 * 1024 < face_cache.MAX_BYTES <= 200 * 1024 * 1024
