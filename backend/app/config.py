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

    # --- Database (queue + saved templates) ---
    # SQLite by default. Swap for Postgres via
    # DATABASE_URL=postgresql+psycopg://user:pass@host/db (also lets several
    # worker processes share one queue safely).
    database_url: str = "sqlite:///./mailer.db"

    # --- Gmail API (OAuth refresh token) ---
    # Create an OAuth client (Desktop) in Google Cloud, grant the
    # https://www.googleapis.com/auth/gmail.send scope, and obtain a refresh
    # token once. See README for the one-time setup.
    email_user: str = ""            # the Gmail address that sends ("From")
    gmail_client_id: str = ""
    gmail_client_secret: str = ""
    gmail_refresh_token: str = ""

    # When true, emails are NOT actually sent — they're logged instead. Lets the
    # whole queue flow be exercised without Gmail credentials.
    dry_run: bool = True

    # --- Queue / workers ---
    # Number of async workers draining the queue. 0 disables the in-app pool
    # (e.g. when running workers as a separate process, or in tests).
    worker_concurrency: int = 4
    # Per-job delivery attempts before it is marked failed.
    job_max_attempts: int = 3
    # Base seconds for exponential retry backoff (attempt n waits base * 2^(n-1)).
    retry_backoff_seconds: int = 10
    # How often an idle worker re-checks the queue (also the retry granularity).
    poll_interval_seconds: float = 2.0

    @property
    def cors_origin_list(self) -> list[str]:
        raw = self.cors_origins.strip()
        if raw == "*" or not raw:
            return ["*"]
        return [o.strip() for o in raw.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
