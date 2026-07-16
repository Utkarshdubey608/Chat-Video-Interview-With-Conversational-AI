"""The worker coroutine: claim a job, deliver it, record the outcome, repeat.

DB access is synchronous and fast; the only slow step (the Gmail network call)
is pushed to a thread so the event loop stays responsive for API requests and
the other workers.
"""

from __future__ import annotations

import asyncio
import logging

from sqlmodel import Session

from app import gmail_client
from app.config import Settings
from app.db import engine
from app.queue import repository as repo

logger = logging.getLogger("worker")


async def process_next(settings: Settings) -> bool:
    """Claim and deliver one job. Returns True if a job was handled, else False
    (queue empty / nothing due). Exposed for tests to drive deterministically."""
    with Session(engine) as session:
        job = repo.claim_next(session)
        if job is None:
            return False

        try:
            await asyncio.to_thread(
                gmail_client.send,
                settings,
                to_email=job.to_email,
                to_name=job.to_name,
                subject=job.subject,
                body=job.body,
                is_html=job.is_html,
            )
        except Exception as exc:  # noqa: BLE001 - one job's failure must not kill the worker
            logger.warning("job %s attempt %s failed: %s", job.id, job.attempts, exc)
            repo.mark_retry_or_fail(session, job, str(exc), settings.retry_backoff_seconds)
            return True

        repo.mark_sent(session, job)
        logger.info("job %s sent to %s", job.id, job.to_email)
        return True


async def worker_loop(
    name: str, settings: Settings, wake: asyncio.Event, stopping: asyncio.Event
) -> None:
    """Drain the queue until told to stop. Sleeps when idle and is woken either
    by a newly-enqueued batch (`wake`) or the poll interval (for retries)."""
    logger.info("worker %s started", name)
    while not stopping.is_set():
        try:
            did_work = await process_next(settings)
        except Exception:  # noqa: BLE001 - never let the loop die
            logger.exception("worker %s crashed on a job; continuing", name)
            did_work = False

        if did_work:
            continue  # stay hot while there is work

        # Idle: wait for a wake signal or the poll interval, whichever first.
        try:
            await asyncio.wait_for(wake.wait(), timeout=settings.poll_interval_seconds)
        except asyncio.TimeoutError:
            pass
        finally:
            wake.clear()
    logger.info("worker %s stopped", name)
