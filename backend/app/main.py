"""FastAPI application entrypoint.

Two things only: pick/save an email template, and send mail to a list of
candidates. No SQL database and no background queue — custom templates live in
the mobile app's Firebase (Firestore) project.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import mailer
from app.config import get_settings
from app.routers import emails, templates

logging.basicConfig(level=logging.INFO)


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        version="2.0.0",
        summary="Send templated interview emails to a list of candidates.",
    )

    # On state so request handlers reach settings without importing globals.
    app.state.settings = settings

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
        """Also reports whether sending is actually configured."""
        return {
            "status": "ok",
            "provider": mailer.provider(settings),
            "sending_ready": mailer.config_hint(settings) is None,
            "hint": mailer.config_hint(settings),
            "firebase_project": settings.firebase_project_id,
        }

    return app


app = create_app()
