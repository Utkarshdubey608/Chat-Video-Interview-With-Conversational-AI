"""Every API path the React app calls, checked against the running backend's spec.

This is the check that decides whether `WEB_FRONTEND_MIGRATION_TASKS.md` is right. It
does not care what the doc claims — it reads the frontend source, extracts the paths, and
asks the live server whether each one exists.

    .venv/bin/python -m uvicorn app.main:app --port 8791 &
    .venv/bin/python scripts/check_frontend_paths.py --base http://127.0.0.1:8791

Each call site is classified:

  OK        the path exists once `/api` becomes `/api/web` — no work beyond the base change
  COMMON    it exists on the shared `/api` surface instead (must use commonBase())
  MOVED     it is gone and the doc names a replacement
  MISSING   it is gone and nothing accounts for it  ← the only failing outcome
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import httpx

FRONTEND = Path(__file__).resolve().parents[2] / "web_version/talbotiq-platform/src"

# Paths the migration doc says are deliberately gone, and what replaces them.
DOCUMENTED_MOVES = {
    "/voices/{}/sample": "POST /api/rt/gemini-preview-token + a browser WS to Google (doc §3.2)",
    "/help/tts": "POST /api/web/help/tts-token + a browser WS to Google (doc §3.3)",
    "/voice/{}": "POST /api/web/sessions/{id}/voice/token + browser WS + /voice/transcript (doc §3.4)",
    # Direct-to-vendor calls with a key in the browser. The migration removes both.
    "/https:/api.deepgram.com/v1/projects": "GET /api/web/avatar/status instead (doc §3.5)",
    "/https:/tavusapi.com/v2": "the /api/tavus/* proxy on the common surface (doc §3.5)",
}

# Call sites that are not backend paths at all.
IGNORE = re.compile(
    r"^/(assets|static|favicon|src|node_modules|@|#)|^/$|\.(png|jpg|svg|css|js|ico|woff2?)$"
    # apiOrigin.ts builds strings from punctuation; those fragments are not paths.
    r"|^/[+.:,;]*$|^/async$|^/{}$"
)

def strip_interpolations(text: str) -> str:
    r"""Replace every `${...}` with `{}`, honouring nested braces.

    A naive `\$\{[^}]*\}` stops at the first `}`, which mangles the very common
    `${q ? `?a=${q}` : ''}` into garbage — and a mangled path then reads as a missing
    route, which is exactly the false alarm this script exists to avoid.
    """
    out, i = [], 0
    while i < len(text):
        if text.startswith("${", i):
            depth, j = 1, i + 2
            while j < len(text) and depth:
                if text[j] == "{":
                    depth += 1
                elif text[j] == "}":
                    depth -= 1
                j += 1
            out.append("{}")
            i = j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)

CALL = re.compile(
    r"""(?:fetch|axios(?:\.\w+)?)\s*\(\s*[`'"]([^`'"]+)[`'"]"""      # fetch('/x')
    r"""|http[A-Za-z]*\s*\(\s*[`'"]([^`'"]+)[`'"]"""                  # http('/x')
    r"""|(?:httpBase|wsBase|commonBase)\(\)\s*\}?([^`'"\s)]*)""",     # `${httpBase()}/x`
    re.X,
)

# A second pass for the api.ts helpers, which call http() with a leading path.
HELPER = re.compile(r"""\bhttp<[^>]*>\(\s*[`'"]([^`'"]+)|\bhttp\(\s*[`'"]([^`'"]+)""")


def normalise(raw: str) -> str:
    """A call site's literal turned into an OpenAPI-shaped path."""
    path = strip_interpolations(raw).split("?")[0].split("#")[0].strip()
    # A literal built as `${httpBase()}/templates` arrives here as `{}/templates`; the
    # leading placeholder is the base, not a path parameter.
    while path.startswith("{}"):
        path = path[2:]
    if not path.startswith("/"):
        path = "/" + path
    path = re.sub(r"/+", "/", path).rstrip("/") or "/"
    # A trailing `{}` left by a query-string interpolation is not part of the path.
    return re.sub(r"\{\}$", "", path).rstrip("/") or "/"


def spec_paths(base: str) -> set[str]:
    spec = httpx.get(f"{base}/openapi.json", timeout=30).json()
    # Reduce {session_id} etc. to {} so a call site's shape can match regardless of the
    # parameter's name.
    return {re.sub(r"\{[^}]+\}", "{}", p) for p in spec["paths"]}


def collect() -> dict[str, list[str]]:
    """Every candidate path in the frontend, mapped to the files that use it."""
    found: dict[str, list[str]] = {}
    for file in sorted(FRONTEND.rglob("*.ts*")):
        if file.name.endswith(".test.ts") or file.name.endswith(".test.tsx"):
            continue
        text = file.read_text(errors="ignore")
        raws = [m for groups in CALL.findall(text) for m in groups if m]
        raws += [m for groups in HELPER.findall(text) for m in groups if m]
        for raw in raws:
            if not raw:
                continue
            path = normalise(raw)
            # Filtered AFTER normalising: apiOrigin.ts and api.ts build strings out of
            # punctuation and keywords, and those fragments only look like paths once a
            # leading slash has been added.
            if path == "/" or len(path) < 2 or IGNORE.search(path):
                continue
            found.setdefault(path, []).append(str(file.relative_to(FRONTEND.parent)))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="http://127.0.0.1:8791")
    parser.add_argument("--verbose", action="store_true", help="also list the OK ones")
    opts = parser.parse_args()

    available = spec_paths(opts.base)
    sites = collect()

    ok, common, moved, missing = [], [], [], []

    for path, files in sorted(sites.items()):
        # The frontend writes paths relative to its base, which after the migration is
        # /api/web. A literal starting with /api is a hardcoded same-origin call.
        stem = path[4:] if path.startswith("/api/") else path
        candidates = {
            f"/api/web{stem}": ok,
            f"/api{stem}": common,
        }
        placed = False
        for candidate, bucket in candidates.items():
            if candidate in available:
                bucket.append((path, candidate, files))
                placed = True
                break
        if placed:
            continue
        if stem in DOCUMENTED_MOVES:
            moved.append((path, DOCUMENTED_MOVES[stem], files))
        else:
            missing.append((path, "", files))

    print(f"Checked {len(sites)} distinct call sites against {len(available)} live routes.\n")

    if opts.verbose and ok:
        print(f"── OK ({len(ok)}) — reachable after the /api → /api/web base change")
        for path, resolved, files in ok:
            print(f"   {path:52} → {resolved}")
        print()

    print(f"── OK: {len(ok)} call sites resolve under /api/web\n")

    if common:
        print(f"── COMMON ({len(common)}) — on the shared /api surface, must use commonBase()")
        for path, resolved, files in common:
            print(f"   {path:52} → {resolved}")
            print(f"      {files[0]}")
        print()

    if moved:
        print(f"── MOVED ({len(moved)}) — deliberately gone, replacement documented")
        for path, note, files in moved:
            print(f"   {path:52}")
            print(f"      → {note}")
            print(f"      {', '.join(sorted(set(files))[:3])}")
        print()

    if missing:
        print(f"── MISSING ({len(missing)}) — no route and no documented replacement")
        for path, _, files in missing:
            print(f"   {path:52}")
            print(f"      {', '.join(sorted(set(files))[:3])}")
        print()

    print("═" * 78)
    print(f"{len(ok)} ok, {len(common)} common-surface, {len(moved)} documented moves, {len(missing)} unaccounted")
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
