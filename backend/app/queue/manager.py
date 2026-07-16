"""Owns the pool of worker tasks and the wake signal, tied to the app lifespan.

The single shared `wake` Event lets `POST /send` nudge idle workers the instant
a batch is enqueued (low latency) while the poll interval remains the safety net
for delayed retries.
"""

from __future__ import annotations

import asyncio
import logging

from sqlmodel import Session

from app.config import Settings
from app.db import engine
from app.queue import repository as repo
from app.queue.worker import worker_loop

logger = logging.getLogger("queue")


class QueueManager:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._wake = asyncio.Event()
        self._stopping = asyncio.Event()
        self._tasks: list[asyncio.Task] = []

    def notify(self) -> None:
        """Wake idle workers — called after a batch is enqueued."""
        self._wake.set()

    async def start(self) -> None:
        # Requeue anything left mid-flight by a previous crash before workers run.
        with Session(engine) as session:
            recovered = repo.recover_orphaned(session)
        if recovered:
            logger.info("recovered %s orphaned job(s) into the queue", recovered)

        n = self._settings.worker_concurrency
        if n <= 0:
            logger.info("worker_concurrency=0 — in-app workers disabled")
            return
        for i in range(n):
            task = asyncio.create_task(
                worker_loop(f"w{i}", self._settings, self._wake, self._stopping)
            )
            self._tasks.append(task)
        logger.info("started %s worker(s)", n)

    async def stop(self) -> None:
        self._stopping.set()
        self._wake.set()  # unblock any idle waiters so they can exit promptly
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
        self._tasks.clear()
