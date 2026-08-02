"""Serves deepgram_web.html plus a /token endpoint that mints a temp token.

The browser must never see DEEPGRAM_API_KEY — which is the whole point of the
architecture, so the spike models it correctly: the key stays here, the page gets
a short-lived JWT.

Run:  .venv/bin/python spikes/serve_web_spike.py   → http://localhost:8765
"""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.request import Request, urlopen

from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("DEEPGRAM_API_KEY", "").strip()
PORT = 8765
HERE = Path(__file__).parent


def grant(ttl: int = 300) -> dict:
    req = Request(
        "https://api.deepgram.com/v1/auth/grant",
        data=json.dumps({"ttl_seconds": ttl}).encode(),
        headers={"Authorization": f"Token {API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(req, timeout=30) as r:
        return json.loads(r.read())


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith("/token"):
            try:
                self._send(200, json.dumps(grant()).encode(), "application/json")
            except Exception as e:
                self._send(500, json.dumps({"error": str(e)}).encode(), "application/json")
            return

        page = HERE / "deepgram_web.html"
        if not page.exists():
            self._send(404, b"deepgram_web.html not found", "text/plain")
            return
        self._send(200, page.read_bytes(), "text/html; charset=utf-8")

    def log_message(self, *args) -> None:  # quieter output
        pass


if __name__ == "__main__":
    if not API_KEY:
        print("DEEPGRAM_API_KEY is not set in backend/.env — cannot run.")
        sys.exit(2)
    print(f"open http://localhost:{PORT}  (ctrl-c to stop)")
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
