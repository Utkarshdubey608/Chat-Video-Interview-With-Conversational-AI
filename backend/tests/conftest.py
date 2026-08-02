"""Shared test setup."""

from __future__ import annotations

import os

os.environ.setdefault("DRY_RUN", "true")
os.environ.setdefault("API_KEY", "")

import pytest  # noqa: E402

from app.ratelimit import _LIMITER  # noqa: E402


@pytest.fixture(autouse=True)
def reset_rate_limiter():
    """Rate-limit counters are process-global, so they leak between tests.

    Without this, a file whose tests each make a request eventually trips the
    limit and later tests fail for reasons unrelated to what they assert.
    """
    _LIMITER.reset()
    yield
    _LIMITER.reset()
