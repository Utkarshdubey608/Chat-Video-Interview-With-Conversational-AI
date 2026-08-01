"""Runtime configuration, loaded from environment variables / a local .env file.

Everything the service needs is declared here so the rest of the code never
reads os.environ directly. See .env.example for the full list.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- App ---
    app_name: str = "TalbotIQ Mailer"
    # Comma-separated list of allowed CORS origins. "*" allows any (dev only).
    cors_origins: str = "*"

    # --- Auth ---
    # Shared secret the Flutter app sends as the `X-API-Key` header. When empty,
    # auth is DISABLED (handy for local dev; set it in any real deploy).
    api_key: str = ""

    # --- Delivery ---
    # When true, emails are NOT actually sent — they're logged instead, and the
    # endpoint still returns per-recipient results. No credentials needed.
    dry_run: bool = True

    # Display name used on the "From" header.
    from_name: str = "TalbotIQ"
    # The Gmail address mail is sent from. Needed by both modes below.
    email_user: str = ""

    # Mode A (simplest): Gmail SMTP with a 16-character App Password.
    email_app_password: str = ""
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587

    # Mode B: Gmail API with an OAuth refresh token — used when all three are
    # set. Handy where outbound SMTP is blocked (some PaaS hosts).
    gmail_client_id: str = ""
    gmail_client_secret: str = ""
    gmail_refresh_token: str = ""

    # How many recipients of one /send call are delivered in parallel.
    send_concurrency: int = 5

    # --- Firebase (saved templates only — same project as the mobile app) ---
    firebase_project_id: str = "talbotiq-9cc4e"
    # Path to a service-account JSON file...
    firebase_credentials_file: str = ""
    # ...or that JSON inline (convenient as a single PaaS env var). If both are
    # empty, Application Default Credentials are used.
    firebase_credentials_json: str = ""
    # Firestore collection holding recruiter-saved templates.
    templates_collection: str = "email_templates"

    @property
    def cors_origin_list(self) -> list[str]:
        raw = self.cors_origins.strip()
        if raw == "*" or not raw:
            return ["*"]
        return [o.strip() for o in raw.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
