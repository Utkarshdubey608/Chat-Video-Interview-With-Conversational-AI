"""The recruiter analytics dashboard.

A hiring dashboard that invented a trend line would be worse than an empty one, so the
tests are about not overstating: no matches produces zeros, the cohort and the scored
population stay distinct, and one recruiter's numbers never include another's candidates.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.web.services import analytics

GENERATED = "2027-03-01T00:00:00+00:00"


def _session(session_id: str, **overrides) -> dict:
    return {
        "id": session_id,
        "recruiterId": "uid-recruiter",
        "templateId": "t1",
        "track": "chat",
        "status": "completed",
        "createdAt": "2027-02-01T10:00:00+00:00",
        "startedAt": "2027-02-01T10:00:00+00:00",
        "completedAt": "2027-02-01T10:10:00+00:00",
        "questions": [],
        "candidate": {"name": "Ada", "email": "ada@x.test"},
        **overrides,
    }


def _template(template_id: str = "t1", **overrides) -> dict:
    return {
        "id": template_id,
        "name": "Backend screen",
        "role": "Backend",
        "rubric": {"kpis": [{"id": "depth", "label": "Depth", "enabled": True, "weight": 1}]},
        **overrides,
    }


def _report(session_id: str, score: int = 70, **overrides) -> dict:
    return {
        "sessionId": session_id,
        "overallScore": score,
        "kpiAverages": {"depth": score},
        "perQuestion": [{"questionId": "q1", "kpiScores": {"depth": score}, "feedback": ""}],
        "recommendation": "yes",
        "generatedAt": "2027-02-01T10:10:00+00:00",
        **overrides,
    }


def _compute(sessions, templates=None, reports=None, **kwargs) -> dict:
    templates = templates or [_template()]
    reports = reports or []
    return analytics.compute(
        sessions,
        {t["id"]: t for t in templates},
        {r["sessionId"]: r for r in reports},
        generated_at=GENERATED,
        **kwargs,
    )


# ── empty state ───────────────────────────────────────────────────────────────


def test_no_data_produces_zeros_and_empty_arrays() -> None:
    """Never sampled or invented data — an empty dashboard is honest."""
    result = _compute([])

    assert result["totals"] == {"created": 0, "started": 0, "completed": 0, "scored": 0}
    assert result["completionRate"] == 0
    assert result["averageOverall"] == 0
    assert result["byTrack"] == []
    assert result["trend"] == []
    assert result["topCandidates"] == []
    assert result["integrityFlagRate"] == 0
    assert result["timeStats"] == {"avgDurationSeconds": 0, "avgTimePerQuestionSeconds": 0}


def test_the_score_buckets_are_always_present() -> None:
    """A chart whose buckets appear and disappear as filters change is unreadable."""
    result = _compute([])
    assert [b["bucket"] for b in result["scoreDistribution"]] == list(analytics.BUCKETS)
    assert all(b["count"] == 0 for b in result["scoreDistribution"])


# ── the funnel counts everything, scores count only what was scored ───────────


def test_the_cohort_and_the_scored_population_are_distinct() -> None:
    sessions = [
        _session("s1"),
        _session("s2", status="in_progress", completedAt=None),
        _session("s3", status="created", startedAt=None, completedAt=None),
    ]
    result = _compute(sessions, reports=[_report("s1")])

    assert result["totals"] == {"created": 3, "started": 2, "completed": 1, "scored": 1}
    assert result["completionRate"] == pytest.approx(1 / 3)


def test_a_session_past_created_counts_as_started_without_a_timestamp() -> None:
    """A session that moved on has been opened even if the start stamp was never
    written."""
    sessions = [_session("s1", status="in_progress", startedAt=None)]
    assert _compute(sessions)["totals"]["started"] == 1


def test_only_scored_sessions_affect_the_average() -> None:
    sessions = [_session("s1"), _session("s2")]
    result = _compute(sessions, reports=[_report("s1", 90)])
    assert result["averageOverall"] == 90
    assert result["totals"]["scored"] == 1


# ── tenant isolation ──────────────────────────────────────────────────────────


def test_another_recruiters_sessions_are_excluded_from_every_aggregate() -> None:
    """A company-wide average that silently included someone else's candidates would be
    wrong in a way nobody would notice."""
    sessions = [_session("mine"), _session("theirs", recruiterId="uid-other")]
    reports = [_report("mine", 50), _report("theirs", 100)]

    result = _compute(sessions, reports=reports, owner_id="uid-recruiter")

    assert result["totals"]["created"] == 1
    assert result["averageOverall"] == 50
    assert [c["sessionId"] for c in result["topCandidates"]] == ["mine"]


def test_ownership_is_checked_before_any_other_filter() -> None:
    sessions = [_session("theirs", recruiterId="uid-other", track="voice")]
    result = _compute(sessions, filters={"track": "voice"}, owner_id="uid-recruiter")
    assert result["totals"]["created"] == 0


# ── filters ───────────────────────────────────────────────────────────────────


def test_the_track_filter_narrows_the_cohort() -> None:
    sessions = [_session("s1", track="chat"), _session("s2", track="voice")]
    assert _compute(sessions, filters={"track": "voice"})["totals"]["created"] == 1


def test_the_template_filter_narrows_the_cohort() -> None:
    sessions = [_session("s1", templateId="t1"), _session("s2", templateId="t2")]
    templates = [_template("t1"), _template("t2", name="Other")]
    assert _compute(sessions, templates, filters={"templateId": "t2"})["totals"]["created"] == 1


def test_the_role_filter_reads_the_templates_role() -> None:
    sessions = [_session("s1", templateId="t1"), _session("s2", templateId="t2")]
    templates = [_template("t1", role="Backend"), _template("t2", role="Frontend")]
    assert _compute(sessions, templates, filters={"role": "Frontend"})["totals"]["created"] == 1


def test_a_session_whose_template_is_gone_groups_as_unspecified() -> None:
    sessions = [_session("s1", templateId="deleted")]
    result = _compute(sessions, templates=[])
    assert [r["role"] for r in result["byRole"]] == [analytics.UNSPECIFIED_ROLE]
    assert [t["name"] for t in result["byTemplate"]] == [analytics.DELETED_TEMPLATE]


# ── date ranges ───────────────────────────────────────────────────────────────


def test_a_date_only_upper_bound_includes_the_whole_day() -> None:
    """`dateTo=2027-02-01` must include everything on the 1st, not only midnight."""
    assert analytics.in_range("2027-02-01T23:30:00+00:00", None, "2027-02-01")
    assert not analytics.in_range("2027-02-02T00:00:01+00:00", None, "2027-02-01")


def test_a_date_only_lower_bound_starts_at_midnight() -> None:
    assert analytics.in_range("2027-02-01T00:00:00+00:00", "2027-02-01", None)
    assert not analytics.in_range("2027-01-31T23:59:59+00:00", "2027-02-01", None)


def test_a_full_timestamp_bound_is_used_as_given() -> None:
    assert analytics.in_range("2027-02-01T12:00:00+00:00", "2027-02-01T10:00:00+00:00", None)
    assert not analytics.in_range("2027-02-01T09:00:00+00:00", "2027-02-01T10:00:00+00:00", None)


def test_an_undated_record_passes_only_without_a_lower_bound() -> None:
    """"Everything up to March" can reasonably include an undated row; "everything since
    March" cannot."""
    assert analytics.in_range(None, None, "2027-03-01")
    assert analytics.in_range(None, None, None)
    assert not analytics.in_range(None, "2027-01-01", None)


def test_an_unparseable_timestamp_behaves_like_a_missing_one() -> None:
    assert analytics.in_range("not a date", None, None)
    assert not analytics.in_range("not a date", "2027-01-01", None)


def test_the_date_filter_narrows_the_cohort() -> None:
    sessions = [
        _session("s1", createdAt="2027-01-15T10:00:00+00:00"),
        _session("s2", createdAt="2027-02-15T10:00:00+00:00"),
    ]
    result = _compute(sessions, filters={"dateFrom": "2027-02-01"})
    assert result["totals"]["created"] == 1


# ── KPI aggregation ───────────────────────────────────────────────────────────


def test_kpis_are_aggregated_by_id_across_different_rubrics() -> None:
    sessions = [_session("s1", templateId="t1"), _session("s2", templateId="t2")]
    templates = [
        _template("t1"),
        _template("t2", rubric={"kpis": [{"id": "depth", "label": "Depth", "enabled": True, "weight": 1}]}),
    ]
    reports = [_report("s1", 80), _report("s2", 60)]

    result = _compute(sessions, templates, reports)
    assert result["kpiAverages"] == [
        {"kpiId": "depth", "label": "Depth", "average": 70, "coverage": 1.0}
    ]


def test_coverage_shows_how_many_sessions_scored_a_kpi() -> None:
    """A KPI only two of fifty sessions used would otherwise look as authoritative as one
    every session scored."""
    sessions = [_session("s1"), _session("s2")]
    reports = [_report("s1", 80), {**_report("s2", 60), "kpiAverages": {}}]

    result = _compute(sessions, reports=reports)
    assert result["kpiAverages"][0]["coverage"] == 0.5


def test_a_kpi_with_no_label_anywhere_falls_back_to_its_id() -> None:
    sessions = [_session("s1")]
    templates = [_template("t1", rubric={"kpis": []})]
    result = _compute(sessions, templates, [_report("s1")])
    assert result["kpiAverages"][0]["label"] == "depth"


def test_kpis_are_ordered_by_average() -> None:
    sessions = [_session("s1")]
    reports = [{**_report("s1"), "kpiAverages": {"low": 20, "high": 90}}]
    result = _compute(sessions, reports=reports)
    assert [k["kpiId"] for k in result["kpiAverages"]] == ["high", "low"]


def test_non_numeric_kpi_values_are_ignored() -> None:
    sessions = [_session("s1")]
    reports = [{**_report("s1"), "kpiAverages": {"depth": "high"}}]
    assert _compute(sessions, reports=reports)["kpiAverages"] == []


# ── groupings ─────────────────────────────────────────────────────────────────


def test_by_track_counts_the_cohort_but_averages_the_scored() -> None:
    sessions = [
        _session("s1", track="voice"),
        _session("s2", track="voice", status="in_progress"),
    ]
    result = _compute(sessions, reports=[_report("s1", 80)])

    voice = next(t for t in result["byTrack"] if t["track"] == "voice")
    assert voice["count"] == 2
    assert voice["completionRate"] == 0.5
    assert voice["averageOverall"] == 80


def test_groupings_are_ordered_by_volume() -> None:
    sessions = [
        _session("s1", track="chat"),
        _session("s2", track="voice"),
        _session("s3", track="voice"),
    ]
    assert [t["track"] for t in _compute(sessions)["byTrack"]] == ["voice", "chat"]


def test_the_trend_is_keyed_on_completion_not_creation() -> None:
    """An invite sent in March and taken in May belongs to May."""
    sessions = [
        _session("s1", createdAt="2027-03-01T10:00:00+00:00", completedAt="2027-05-02T10:00:00+00:00")
    ]
    result = _compute(sessions, reports=[_report("s1", 75)])
    assert result["trend"] == [{"date": "2027-05-02", "count": 1, "averageOverall": 75}]


def test_the_trend_falls_back_to_the_report_time() -> None:
    sessions = [_session("s1", completedAt=None)]
    reports = [{**_report("s1"), "generatedAt": "2027-04-04T10:00:00+00:00"}]
    assert _compute(sessions, reports=reports)["trend"][0]["date"] == "2027-04-04"


def test_the_trend_is_chronological() -> None:
    sessions = [
        _session("s1", completedAt="2027-05-02T10:00:00+00:00"),
        _session("s2", completedAt="2027-05-01T10:00:00+00:00"),
    ]
    result = _compute(sessions, reports=[_report("s1"), _report("s2")])
    assert [d["date"] for d in result["trend"]] == ["2027-05-01", "2027-05-02"]


# ── time stats ────────────────────────────────────────────────────────────────


def test_duration_is_measured_from_the_session() -> None:
    result = _compute([_session("s1")], reports=[_report("s1")])
    assert result["timeStats"]["avgDurationSeconds"] == 600


def test_a_timed_track_uses_real_per_question_spans() -> None:
    session = _session(
        "s1",
        track="chat",
        questions=[
            {
                "answerStartedAt": "2027-02-01T10:00:00+00:00",
                "submittedAt": "2027-02-01T10:00:40+00:00",
            }
        ],
    )
    result = _compute([session], reports=[_report("s1")])
    assert result["timeStats"]["avgTimePerQuestionSeconds"] == 40


def test_a_conversation_derives_per_question_time_from_the_total() -> None:
    """Its turns are all stamped at finalise time, so the total is the only measure
    available."""
    session = _session("s1", track="voice")
    report = {**_report("s1"), "perQuestion": [{"questionId": "a"}, {"questionId": "b"}]}
    result = _compute([session], reports=[report])
    assert result["timeStats"]["avgTimePerQuestionSeconds"] == 300


def test_an_unmeasurable_session_is_excluded_rather_than_counted_as_zero() -> None:
    session = _session("s1", startedAt=None, completedAt=None, track="voice")
    assert analytics.average_time_per_question(session, _report("s1")) is None


# ── recommendations, integrity, ranking ───────────────────────────────────────


def test_a_report_with_no_recommendation_counts_as_unknown() -> None:
    """Omitting it would make the distribution add up to fewer interviews than were
    run."""
    reports = [_report("s1"), {**_report("s2"), "recommendation": None}]
    sessions = [_session("s1"), _session("s2")]
    counts = {
        entry["recommendation"]: entry["count"]
        for entry in _compute(sessions, reports=reports)["recommendationDistribution"]
    }
    assert counts == {"yes": 1, "unknown": 1}


def test_the_integrity_rate_is_over_scored_sessions() -> None:
    sessions = [
        _session("s1", integrityEvents=[{"type": "tab_switch"}]),
        _session("s2", integrityEvents=[]),
    ]
    result = _compute(sessions, reports=[_report("s1"), _report("s2")])
    assert result["integrityFlagRate"] == 0.5


def test_top_candidates_are_ranked_and_capped() -> None:
    sessions = [_session(f"s{i}") for i in range(15)]
    reports = [_report(f"s{i}", score=i * 5) for i in range(15)]
    top = _compute(sessions, reports=reports)["topCandidates"]

    assert len(top) == analytics.TOP_CANDIDATE_LIMIT
    assert top[0]["overallScore"] == 70
    assert top == sorted(top, key=lambda c: c["overallScore"], reverse=True)


def test_a_candidate_with_no_name_gets_a_placeholder() -> None:
    sessions = [_session("s1", candidate={})]
    assert _compute(sessions, reports=[_report("s1")])["topCandidates"][0]["name"] == "Candidate"


# ── the route ─────────────────────────────────────────────────────────────────


def test_the_dashboard_is_served(authed_client: TestClient, fake_store) -> None:
    fake_store.templates.docs["t1"] = _template()
    fake_store.sessions.docs["s1"] = _session("s1")
    fake_store.reports.docs["s1"] = _report("s1", 88)

    body = authed_client.get("/api/web/analytics").json()

    assert body["totals"]["scored"] == 1
    assert body["averageOverall"] == 88
    assert body["topCandidates"][0]["sessionId"] == "s1"
    assert body["generatedAt"]


def test_the_route_scopes_to_the_caller(authed_client: TestClient, fake_store) -> None:
    fake_store.templates.docs["t1"] = _template()
    fake_store.sessions.docs["theirs"] = _session("theirs", recruiterId="uid-other")
    fake_store.reports.docs["theirs"] = _report("theirs", 100)

    assert authed_client.get("/api/web/analytics").json()["totals"]["created"] == 0


def test_the_route_passes_its_filters_through(authed_client: TestClient, fake_store) -> None:
    fake_store.templates.docs["t1"] = _template()
    fake_store.sessions.docs["s1"] = _session("s1", track="chat")

    body = authed_client.get("/api/web/analytics", params={"track": "voice"}).json()
    assert body["totals"]["created"] == 0


def test_analytics_requires_a_token() -> None:
    assert TestClient(create_app()).get("/api/web/analytics").status_code == 401
