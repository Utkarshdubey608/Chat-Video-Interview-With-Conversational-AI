"""Phase 9 — retire the Firestore credential collections.

The app no longer reads or writes these. What remains is cleanup:

* ``recruiter_keys/{recruiterId}`` — a recruiter's vendor API keys. Under the old
  ``firestore.rules`` these were readable by **any signed-in user**, because a
  candidate's device needed them to create a Tavus conversation and score
  client-side.
* ``candidate_keys/{uid}`` — a candidate's own key backup (owner-only).
* ``interviews/*.keyOverrides`` — per-test pinned keys, now ignored by the app.

**Deleting these documents does not undo the exposure.** Every key that was ever
written to ``recruiter_keys`` should be treated as compromised and rotated at the
vendor. This script's first job is to tell you exactly which keys those are, so
run it (read-only) BEFORE deleting anything.

Nothing is written unless ``--apply`` is passed.

    # 1. See what exists and what needs rotating. Reads only.
    .venv/bin/python scripts/purge_key_collections.py

    # 2. Rotate at the vendors. Then delete.
    .venv/bin/python scripts/purge_key_collections.py --apply

Key VALUES are never printed or written to disk — only which fields were present
and a 4-character tail, which is enough to identify a key in a vendor console.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings  # noqa: E402
from app.firebase import FirestoreUnavailable, get_db  # noqa: E402

KEY_COLLECTIONS = ("recruiter_keys", "candidate_keys")
INTERVIEWS = "interviews"

# The credential fields the old RecruiterCredentials wrote.
KEY_FIELDS = (
    "tavusKey",
    "geminiKey",
    "humeKey",
    "deepgramKey",
    "awsKey",
    "anthropicKey",
)

VENDOR_CONSOLES = {
    "tavusKey": "Tavus → Settings → API Keys",
    "geminiKey": "https://aistudio.google.com/apikey",
    "deepgramKey": "Deepgram Console → Settings → API Keys",
    "humeKey": "Hume (batch API discontinued — revoke, no replacement needed)",
    "awsKey": "AWS IAM → Access keys",
    "anthropicKey": "https://console.anthropic.com/settings/keys",
}


def tail(value: object) -> str:
    """A 4-char tail — enough to find the key in a vendor console, not to use it."""
    text = value if isinstance(value, str) else ""
    text = text.strip()
    if not text:
        return "(blank)"
    return f"…{text[-4:]}" if len(text) > 4 else "(short)"


def scan(db) -> tuple[dict[str, list], set[str]]:
    """Read the credential docs. Returns per-collection rows and the field names
    that were actually populated somewhere."""
    found: dict[str, list] = {}
    exposed: set[str] = set()

    for collection in KEY_COLLECTIONS:
        rows = []
        for doc in db.collection(collection).stream():
            data = doc.to_dict() or {}
            present = {f: tail(data.get(f)) for f in KEY_FIELDS if str(data.get(f) or "").strip()}
            rows.append({"id": doc.id, "keys": present})
            # Only recruiter_keys was broadly readable; candidate_keys was
            # owner-only, so its contents are not treated as exposed.
            if collection == "recruiter_keys":
                exposed.update(present)
        found[collection] = rows

    return found, exposed


def scan_interviews(db) -> list[str]:
    """Interview ids still carrying a `keyOverrides` map."""
    ids = []
    for doc in db.collection(INTERVIEWS).stream():
        overrides = (doc.to_dict() or {}).get("keyOverrides")
        if isinstance(overrides, dict) and overrides:
            ids.append(doc.id)
    return ids


def report(found: dict[str, list], exposed: set[str], interview_ids: list[str]) -> None:
    for collection, rows in found.items():
        print(f"\n── {collection} ── {len(rows)} document(s)")
        for row in rows:
            keys = ", ".join(f"{k}={v}" for k, v in row["keys"].items()) or "(no keys set)"
            print(f"   {row['id']}: {keys}")

    print(f"\n── {INTERVIEWS}.keyOverrides ── {len(interview_ids)} document(s)")
    for doc_id in interview_ids[:20]:
        print(f"   {doc_id}")
    if len(interview_ids) > 20:
        print(f"   … and {len(interview_ids) - 20} more")

    print("\n" + "=" * 70)
    if exposed:
        print("ROTATE THESE — they were readable by any signed-in user:")
        for field in sorted(exposed):
            print(f"   · {field:<14} {VENDOR_CONSOLES.get(field, '')}")
        print("\nDeleting the documents does NOT undo the exposure. Rotate first.")
    else:
        print("No populated keys found in recruiter_keys — nothing to rotate.")
    print("=" * 70)


def purge(db, found: dict[str, list], interview_ids: list[str]) -> None:
    for collection, rows in found.items():
        for row in rows:
            db.collection(collection).document(row["id"]).delete()
            print(f"   deleted {collection}/{row['id']}")

    for doc_id in interview_ids:
        # Field-level delete: the interview itself must survive.
        from google.cloud import firestore  # imported here so a dry run needs no import

        db.collection(INTERVIEWS).document(doc_id).update(
            {"keyOverrides": firestore.DELETE_FIELD}
        )
        print(f"   cleared keyOverrides on {INTERVIEWS}/{doc_id}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="actually delete. Without this the script only reads.",
    )
    args = parser.parse_args()

    settings = get_settings()
    try:
        db = get_db(settings)
    except FirestoreUnavailable as exc:
        print(f"Firestore is not reachable: {exc}")
        return 2

    print(f"project: {settings.firebase_project_id}")
    found, exposed = scan(db)
    interview_ids = scan_interviews(db)
    report(found, exposed, interview_ids)

    total = sum(len(rows) for rows in found.values()) + len(interview_ids)
    if not args.apply:
        print(f"\nDRY RUN — nothing was changed. {total} document(s) would be touched.")
        print("Rotate the keys above, then re-run with --apply.")
        return 0

    if not total:
        print("\nNothing to delete.")
        return 0

    print(f"\nDeleting {total} document(s)…")
    purge(db, found, interview_ids)
    print("\nDone. Confirm the keys above have been rotated at their vendors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
