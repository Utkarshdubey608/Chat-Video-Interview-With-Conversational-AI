"""Brevo REST — the verified-sender list, and nothing else.

Sending goes over SMTP (`app.mailer`); this exists only so the recruiter's sender
picker can show which addresses Brevo will actually accept. That matters because
sending From an unverified address does not error — the mail is silently dropped or
spam-foldered, which looks like the candidate ignoring an invite that never arrived.

Branded sending from your own domain (rather than Brevo's default `…@brevosend.com`
subdomain) needs the domain added with SPF and DKIM records; this endpoint surfaces
which senders have cleared that.

The key is server-only. It is never sent to a client and never given a `VITE_` name.
"""

from __future__ import annotations

import logging

from app.providers.base import ProviderClient

logger = logging.getLogger("providers.brevo")


class BrevoClient(ProviderClient):
    name = "Brevo"
    env_var = "BREVO_API_KEY"
    base_url = "https://api.brevo.com/v3"

    @property
    def api_key(self) -> str:
        return self.settings.brevo_api_key

    def auth_headers(self) -> dict[str, str]:
        # Brevo uses its own header name, not a bearer token.
        return {"api-key": self.api_key.strip(), "accept": "application/json"}

    async def list_senders(self) -> list[dict]:
        """Every sender configured on the account.

        Returns `[]` when no key is set rather than raising: the picker then falls
        back to manual entry, which is a working path. A real API failure DOES raise,
        because that is a misconfiguration the recruiter should be told about instead
        of seeing an empty list they cannot explain.
        """
        if not self.is_configured:
            return []

        payload = await self.request("GET", "/senders")
        senders = (payload or {}).get("senders") or []

        return [
            {
                "email": sender.get("email") or "",
                "name": sender.get("name") or "",
                # Absent means active — Brevo omits the flag for a verified sender, so
                # defaulting to False would hide every usable address.
                "active": sender.get("active") is not False,
            }
            for sender in senders
            if isinstance(sender, dict) and sender.get("email")
        ]
