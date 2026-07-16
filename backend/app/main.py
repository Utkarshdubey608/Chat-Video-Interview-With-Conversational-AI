"""FastAPI application entrypoint.

On startup it creates tables, recovers any orphaned jobs, and launches the async
worker pool that drains the email queue. Settings and the queue manager are put
on `app.state` so request handlers can enqueue and nudge workers.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.db import init_db
from app.queue.manager import QueueManager
from app.routers import emails, templates

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    await app.state.queue.start()  # launch the worker pool
    try:
        yield
    finally:
        await app.state.queue.stop()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        version="1.0.0",
        summary="Queued interview-invite email delivery (Gmail API) + template storage.",
        lifespan=lifespan,
    )

    # On state so request handlers can reach them without a running lifespan
    # (e.g. in tests). The worker pool itself only starts under lifespan.
    app.state.settings = settings
    app.state.queue = QueueManager(settings)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(templates.router)
    app.include_router(emails.router)

    @app.get("/health", tags=["meta"])
    async def health() -> dict:
        return {
            "status": "ok",
            "dry_run": settings.dry_run,
            "workers": settings.worker_concurrency,
        }

    return app


app = create_app()
