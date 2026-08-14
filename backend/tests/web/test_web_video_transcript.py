"""Turning a submitted video answer into transcript turns.

Small, but load-bearing: this pairing is what lets the Video track's results, scoring
and speech metrics reuse the Voice path instead of needing a separate shape.
"""

from __future__ import annotations

from itertools import count

from app.web.services.video_transcript import build_turns

NOW = "2027-01-15T12:00:00+00:00"


def _ids():
    counter = count(1)
    return lambda: f"id-{next(counter)}"


def test_a_question_and_answer_pair_is_produced() -> None:
    turns = build_turns(
        {"text": "Why this role?", "answerText": "Because I like parsers."},
        0,
        NOW,
        new_id=_ids(),
    )

    assert turns == [
        {
            "id": "id-1",
            "role": "interviewer",
            "content": "Why this role?",
            "turnType": "question",
            "questionIndex": 0,
            "createdAt": NOW,
        },
        {
            "id": "id-2",
            "role": "candidate",
            "content": "Because I like parsers.",
            "questionIndex": 0,
            "createdAt": NOW,
        },
    ]


def test_both_turns_share_the_question_index() -> None:
    """That is how the results view pairs them back up, and how per-question scoring
    knows which answer belongs to which question."""
    turns = build_turns({"text": "Q", "answerText": "A"}, 3, NOW, new_id=_ids())
    assert [turn["questionIndex"] for turn in turns] == [3, 3]


def test_an_unanswered_question_still_produces_a_candidate_turn() -> None:
    """The turn's existence records that they were asked and had their chance — a
    missing turn would not."""
    turns = build_turns({"text": "Q"}, 0, NOW, new_id=_ids())
    assert turns[1]["role"] == "candidate"
    assert turns[1]["content"] == ""


def test_a_missing_question_text_is_empty_rather_than_none() -> None:
    """`None` in a transcript would render as the string "None" downstream."""
    turns = build_turns({}, 0, NOW, new_id=_ids())
    assert turns[0]["content"] == ""


def test_only_the_interviewer_turn_is_marked_as_a_question() -> None:
    turns = build_turns({"text": "Q", "answerText": "A"}, 0, NOW, new_id=_ids())
    assert turns[0]["turnType"] == "question"
    assert "turnType" not in turns[1]


def test_the_two_turns_get_distinct_ids() -> None:
    turns = build_turns({"text": "Q", "answerText": "A"}, 0, NOW)
    assert turns[0]["id"] != turns[1]["id"]
    assert len(turns[0]["id"]) > 10
