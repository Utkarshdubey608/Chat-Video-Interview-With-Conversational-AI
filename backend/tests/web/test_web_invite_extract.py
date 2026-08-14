"""Parsing a candidate list, and the Brevo delivery webhook.

The extractor is deliberately permissive — the recruiter's review table is the real
gate — so what matters is that every guess it makes is reported as a warning, and that
no candidate is silently lost.
"""

from __future__ import annotations

import asyncio
import io

import pytest

from app.web.routes import brevo_webhook
from app.web.services import invite_extract


def _extract(data: bytes, *, filename: str, content_type: str = "", role: str = "Backend") -> dict:
    return asyncio.run(
        invite_extract.extract_candidates(
            data, content_type=content_type, filename=filename, fallback_role=role
        )
    )


def _xlsx(rows: list[list[object]]) -> bytes:
    from openpyxl import Workbook

    workbook = Workbook()
    for row in rows:
        workbook.active.append(row)
    buffer = io.BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()


# ── email validation ──────────────────────────────────────────────────────────


@pytest.mark.parametrize("email", ["a@b.co", "ada.lovelace+tag@sub.example.com"])
def test_plausible_addresses_are_valid(email: str) -> None:
    assert invite_extract.is_valid_email(email)


@pytest.mark.parametrize("email", ["", "  ", "no-at-sign", "a@b", "a@b.c", "a b@c.com"])
def test_implausible_addresses_are_flagged(email: str) -> None:
    assert not invite_extract.is_valid_email(email)


# ── CSV ───────────────────────────────────────────────────────────────────────


def test_a_headered_csv_maps_both_columns() -> None:
    csv = b"Name,Email,Role\nAda,ada@x.test,Backend\nGrace,grace@x.test,Frontend\n"
    result = _extract(csv, filename="list.csv")

    assert [r["email"] for r in result["rows"]] == ["ada@x.test", "grace@x.test"]
    assert [r["role"] for r in result["rows"]] == ["Backend", "Frontend"]
    assert all(r["valid"] for r in result["rows"])
    # A fully-mapped file should produce no guesses to warn about.
    assert result["warnings"] == []


def test_a_headerless_csv_warns_and_uses_the_batch_role() -> None:
    """The first row must not be lost — it is a candidate, not a header."""
    result = _extract(b"ada@x.test\ngrace@x.test\n", filename="list.csv", role="QA")

    assert len(result["rows"]) == 2
    assert all(r["role"] == "QA" for r in result["rows"])
    assert any("No email/role header" in w for w in result["warnings"])


def test_a_header_label_is_distinguished_from_an_address() -> None:
    """"Email" is a header; "ada@x.test" is data, even in the first row."""
    rows, headered = invite_extract.candidates_from_rows([["Email"], ["ada@x.test"]], "R")
    assert headered is True
    assert [r["email"] for r in rows] == ["ada@x.test"]

    rows, headered = invite_extract.candidates_from_rows([["ada@x.test"]], "R")
    assert headered is False
    assert [r["email"] for r in rows] == ["ada@x.test"]


def test_a_semicolon_delimited_export_is_sniffed() -> None:
    """European Excel exports semicolons; parsed as one column it would find nothing."""
    result = _extract(b"Email;Role\nada@x.test;Backend\n", filename="list.csv")
    assert [r["email"] for r in result["rows"]] == ["ada@x.test"]
    assert result["rows"][0]["role"] == "Backend"


def test_a_tab_separated_file_works() -> None:
    result = _extract(b"Email\tRole\nada@x.test\tBackend\n", filename="list.tsv")
    assert [r["email"] for r in result["rows"]] == ["ada@x.test"]


def test_a_byte_order_mark_is_stripped() -> None:
    """Excel writes one, and it would otherwise become part of the first header."""
    result = _extract("﻿Email,Role\nada@x.test,Backend\n".encode(), filename="list.csv")
    assert [r["email"] for r in result["rows"]] == ["ada@x.test"]


def test_a_ragged_row_falls_back_to_any_address_in_it() -> None:
    """A blank named column must not drop a candidate over a messy export."""
    csv = b"Name,Email,Role\nAda,,Backend\nGrace,grace@x.test,Frontend\n"
    result = _extract(csv, filename="list.csv")
    # Ada's row has no address at all, so it is dropped; Grace survives.
    assert [r["email"] for r in result["rows"]] == ["grace@x.test"]


def test_an_address_in_an_unnamed_column_is_still_found() -> None:
    csv = b"Name,Email,Role\nada@x.test,,Backend\n"
    result = _extract(csv, filename="list.csv")
    assert [r["email"] for r in result["rows"]] == ["ada@x.test"]


def test_a_missing_role_column_falls_back_to_the_batch_role() -> None:
    result = _extract(b"Email\nada@x.test\n", filename="list.csv", role="Platform")
    assert result["rows"][0]["role"] == "Platform"


@pytest.mark.parametrize("header", ["E-mail", "MAIL", "email address"])
def test_email_header_variants_are_recognised(header: str) -> None:
    result = _extract(f"{header}\nada@x.test\n".encode(), filename="list.csv")
    assert [r["email"] for r in result["rows"]] == ["ada@x.test"]
    assert result["warnings"] == []


@pytest.mark.parametrize("header", ["Role", "Position", "Job Title", "Designation"])
def test_role_header_variants_are_recognised(header: str) -> None:
    result = _extract(f"Email,{header}\nada@x.test,Backend\n".encode(), filename="list.csv")
    assert result["rows"][0]["role"] == "Backend"


# ── XLSX ──────────────────────────────────────────────────────────────────────


def test_an_xlsx_is_read_column_wise() -> None:
    data = _xlsx([["Email", "Role"], ["ada@x.test", "Backend"], ["grace@x.test", "Frontend"]])
    result = _extract(data, filename="list.xlsx")
    assert [r["email"] for r in result["rows"]] == ["ada@x.test", "grace@x.test"]
    assert [r["role"] for r in result["rows"]] == ["Backend", "Frontend"]


def test_blank_rows_are_ignored() -> None:
    data = _xlsx([["Email"], ["ada@x.test"], [None], [""], ["grace@x.test"]])
    result = _extract(data, filename="list.xlsx")
    assert len(result["rows"]) == 2


def test_the_legacy_xls_format_tells_the_recruiter_what_to_do() -> None:
    """openpyxl cannot read it, and a silent empty result would look like an empty
    file."""
    result = _extract(b"\xd0\xcf\x11\xe0garbage", filename="old.xls")
    assert result["rows"] == []
    assert any(".xlsx or .csv" in w for w in result["warnings"])


def test_a_corrupt_spreadsheet_says_so() -> None:
    result = _extract(b"not really a spreadsheet", filename="list.xlsx")
    assert result["rows"] == []
    assert any("could not be read" in w for w in result["warnings"])


# ── unstructured ──────────────────────────────────────────────────────────────


def test_a_text_file_is_scanned_by_pattern_and_warns() -> None:
    """Roles cannot be paired from prose, so the guess is reported."""
    text = b"Contact ada@x.test or grace@x.test for details."
    result = _extract(text, filename="notes.txt", content_type="text/plain", role="QA")

    assert [r["email"] for r in result["rows"]] == ["ada@x.test", "grace@x.test"]
    assert all(r["role"] == "QA" for r in result["rows"])
    assert any("Unstructured file" in w for w in result["warnings"])


def test_an_unreadable_document_reports_no_addresses() -> None:
    result = _extract(b"%PDF-1.4 broken", filename="cv.pdf", content_type="application/pdf")
    assert result["rows"] == []
    assert any("No email addresses found" in w for w in result["warnings"])


def test_an_empty_upload_is_handled() -> None:
    result = _extract(b"", filename="empty.csv")
    assert result["rows"] == []
    assert any("No email addresses found" in w for w in result["warnings"])


# ── de-duplication ────────────────────────────────────────────────────────────


def test_duplicates_are_removed_case_insensitively_and_counted() -> None:
    """One mailbox; inviting it twice sends the same person two different interviews."""
    csv = b"Email\nAda@X.test\nada@x.test\nADA@X.TEST\ngrace@x.test\n"
    result = _extract(csv, filename="list.csv")

    assert [r["email"] for r in result["rows"]] == ["Ada@X.test", "grace@x.test"]
    assert any("2 duplicate emails removed" in w for w in result["warnings"])


def test_a_single_duplicate_is_reported_in_the_singular() -> None:
    result = _extract(b"Email\nada@x.test\nada@x.test\n", filename="list.csv")
    assert any("1 duplicate email removed" in w for w in result["warnings"])


def test_the_first_spelling_is_the_one_kept() -> None:
    """It is what the recruiter typed, and what the review table should show."""
    rows, _ = invite_extract.deduplicate(
        [{"email": "Ada@X.test", "role": "R"}, {"email": "ada@x.test", "role": "R"}], "R"
    )
    assert [r["email"] for r in rows] == ["Ada@X.test"]


def test_invalid_addresses_are_kept_but_flagged() -> None:
    """Dropping them silently would hide a typo the recruiter could fix."""
    result = _extract(b"Email\nada@x.test\nbroken-address\n", filename="list.csv")
    by_email = {r["email"]: r["valid"] for r in result["rows"]}
    assert by_email == {"ada@x.test": True, "broken-address": False}


# ── Brevo webhook ─────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "event,expected",
    [
        ("delivered", "delivered"),
        ("hardBounce", "bounced"),
        ("soft_bounce", "bounced"),
        ("spam", "spam"),
        ("blocked", "failed"),
        ("deferred", "failed"),
        ("uniqueOpened", "opened"),
        ("click", "clicked"),
    ],
)
def test_events_map_onto_invite_statuses(event: str, expected: str) -> None:
    assert brevo_webhook.map_event(event) == expected


@pytest.mark.parametrize("event", ["request", "sent", "unsubscribed", "", None, "nonsense"])
def test_queue_events_are_ignored(event) -> None:
    """These describe Brevo's own queue, not whether the candidate got the mail —
    letting them overwrite a `delivered` would lose information."""
    assert brevo_webhook.map_event(event) is None


def test_the_interview_id_is_read_from_the_echoed_header() -> None:
    payload = {"X-Mailin-custom": '{"interviewId":"abc123"}'}
    assert brevo_webhook.interview_id_from(payload) == "abc123"


@pytest.mark.parametrize("key", ["X-Mailin-custom", "x-mailin-custom", "mailincustom", "tag"])
def test_every_field_name_brevo_uses_is_checked(key: str) -> None:
    """Which one arrives depends on the event type."""
    assert brevo_webhook.interview_id_from({key: '{"interviewId":"x"}'}) == "x"


def test_an_already_parsed_object_works_too() -> None:
    assert brevo_webhook.interview_id_from({"tag": {"interviewId": "x"}}) == "x"


@pytest.mark.parametrize(
    "payload",
    [{}, {"tag": ""}, {"tag": "not json"}, {"tag": '{"other":"x"}'}, {"tag": "[1,2]"}],
)
def test_a_missing_or_malformed_correlation_id_is_none(payload: dict) -> None:
    """The route then falls back to matching by email."""
    assert brevo_webhook.interview_id_from(payload) is None
