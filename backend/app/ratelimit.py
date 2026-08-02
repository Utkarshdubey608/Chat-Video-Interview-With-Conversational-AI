"""Per-user rate limiting for the routes that cost money.

Two things make these endpoints worth limiting beyond authentication: minting a
Gemini Live token hands out a real credential, and `generate`/`transcribe`/
`jobs` bill per call. Auth answers "is this a real user"; it does not answer
"has this user asked 10,000 times in a minute".

**Scope and honest limitations.** This is an in-process sliding window: counters
live in this worker's memory. They reset on restart and are *not* shared between
replicas, so N workers allow roughly N× the configured limit. That is a
deliberate trade — it adds no infrastructure and stops the runaway cases
(a retry loop, a script with a stolen ID token) without a Redis dependency. If
this service is ever scaled out and the limits must be exact, replace
`_LIMITER` with a shared store; the dependency surface stays the same.
"""

from __future__ import annotations

import logging
import math
import threading
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Callable

from fastapi import Depends, HTTPException, Request, status

from app.config import Settings
from app.security import AuthedUser, require_firebase_user

logger = logging.getLogger("ratelimit")

# Guards against unbounded memory if many distinct users are seen. Well above
# any realistic concurrent-user count for this service.
_MAX_TRACKED_KEYS = 50_000


@dataclass(frozen=True)
class Rule:
    """`limit` requests per `window_seconds`."""

    limit: int
    window_seconds: int


class SlidingWindowLimiter:
    """Counts hits per key inside a moving time window.

    A sliding window rather than fixed buckets: a fixed window lets a caller
    fire `2 × limit` across a boundary, which is exactly the burst that hurts on
    a billable endpoint.
    """

    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def hit(self, key: str, rule: Rule) -> float | None:
        """Record a request. Returns seconds to wait if it should be refused."""
        if rule.limit <= 0:
            return None

        now = time.monotonic()
        cutoff = now - rule.window_seconds

        with self._lock:
            if len(self._hits) > _MAX_TRACKED_KEYS:
                self._evict_stale(cutoff)

            timestamps = self._hits[key]
            while timestamps and timestamps[0] <= cutoff:
                timestamps.popleft()

            if len(timestamps) >= rule.limit:
                # Refusals do NOT count as hits — otherwise a client that keeps
                # retrying could hold itself out indefinitely.
                return max(timestamps[0] + rule.window_seconds - now, 0.0)

            timestamps.append(now)
            return None

    def _evict_stale(self, cutoff: float) -> None:
        """Drop keys with no recent activity. Caller holds the lock."""
        for key in [k for k, v in self._hits.items() if not v or v[-1] <= cutoff]:
            del self._hits[key]

    def reset(self) -> None:
        """Clear all counters — for tests."""
        with self._lock:
            self._hits.clear()


_LIMITER = SlidingWindowLimiter()


def limit_by_user(bucket: str, rule_for: Callable[[Settings], Rule]):
    """A dependency that rate-limits `bucket` per authenticated user.

    `rule_for` reads the limit from settings at request time, so limits can be
    tuned by environment without touching route definitions.

    Depending on `require_firebase_user` here does not re-verify the token:
    FastAPI caches a dependency's result within a request, so a route that also
    depends on it resolves the same `AuthedUser`.
    """

    async def dependency(
        request: Request,
        user: AuthedUser = Depends(require_firebase_user),
    ) -> None:
        settings: Settings = request.app.state.settings
        if not settings.rate_limit_enabled:
            return

        rule = rule_for(settings)
        retry_after = _LIMITER.hit(f"{bucket}:{user.uid}", rule)
        if retry_after is None:
            return

        # uid only — never the token, and no request body.
        logger.warning("rate limit hit: bucket=%s uid=%s", bucket, user.uid)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"Too many requests. Try again in {math.ceil(retry_after)} seconds."
            ),
            headers={"Retry-After": str(max(math.ceil(retry_after), 1))},
        )

    return dependency


# --- the buckets ------------------------------------------------------------
# Separate buckets so a burst of scoring calls cannot block a candidate from
# starting their interview, and vice versa.

RateLimitLiveToken = Depends(
    limit_by_user(
        "live-token",
        lambda s: Rule(s.rate_limit_live_token, s.rate_limit_window_seconds),
    )
)

RateLimitGenerate = Depends(
    limit_by_user(
        "gemini-generate",
        lambda s: Rule(s.rate_limit_generate, s.rate_limit_window_seconds),
    )
)

RateLimitMedia = Depends(
    limit_by_user(
        "media",
        lambda s: Rule(s.rate_limit_media, s.rate_limit_window_seconds),
    )
)
