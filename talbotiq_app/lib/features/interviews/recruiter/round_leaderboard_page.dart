// lib/features/interviews/recruiter/round_leaderboard_page.dart
//
// One round's candidates, ranked by score. The recruiter's answer to "who did
// best, and why".
//
// Works for every round kind, because both the interview scorer and the résumé
// scorer write `result.overallScore` — the ranking needs no knowledge of what was
// scored. What IS résumé-specific is the expanded detail: the skill breakdown and
// the raw extracted text, shown behind a disclosure so a recruiter can read
// exactly what the AI judged. A score whose basis cannot be read is not
// reviewable, which is the whole reason the backend stores the text.
//
// Ordering by a nested field makes Firestore drop documents that lack it, so
// candidates with no score are ABSENT here rather than ranked last. That is
// correct — an unscored candidate has no rank — but it means this screen must say
// how many are missing instead of looking complete. See the footer.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import 'package:talbotiq/core/utils/date_format.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/models/interview_round.dart';
import 'package:talbotiq/features/interviews/models/resume_submission.dart';
import 'package:talbotiq/features/interviews/models/test_summary.dart';
import 'package:talbotiq/features/interviews/recruiter/test_candidates_page.dart';
import 'package:talbotiq/features/interviews/recruiter/widgets/recruiter_action_bar.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';
import 'package:talbotiq/shared/widgets/app_message_state.dart';

class RoundLeaderboardPage extends StatefulWidget {
  final TestSummary test;

  /// The round to rank. Null ranks the whole test, which is what a test with no
  /// timeline needs.
  final InterviewRound? round;

  const RoundLeaderboardPage({super.key, required this.test, this.round});

  @override
  State<RoundLeaderboardPage> createState() => _RoundLeaderboardPageState();
}

class _RoundLeaderboardPageState extends State<RoundLeaderboardPage> {
  final _scroll = ScrollController();

  final List<Interview> _ranked = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  /// Everyone assigned to the round, scored or not. -1 while unknown.
  int _assigned = -1;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _testId => widget.test.testId;
  String? get _roundId => widget.round?.id;

  InterviewRepository get _repo => context.read<InterviewRepository>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _refresh();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || !_hasMore) return;
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _ranked.clear();
      _cursor = null;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
    final n = await _repo.countForRecruiter(
        recruiterId: _uid, testId: _testId, roundId: _roundId);
    if (!mounted) return;
    setState(() => _assigned = n);
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await _repo.fetchLeaderboardPage(
        recruiterId: _uid,
        testId: _testId,
        roundId: _roundId,
        startAfter: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _ranked.addAll(page.items);
        _cursor = page.lastDoc ?? _cursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _hasMore = false;
      });
    }
  }

  void _openAllCandidates() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TestCandidatesPage(test: widget.test, round: widget.round),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Leaderboard',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
        ),
      ),
      body: Column(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 18),
              child: Text(
                (widget.round?.title ?? widget.test.title).toLowerCase(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: _openAllCandidates,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_alt_outlined,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'All candidates',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null && _ranked.isEmpty) {
      return AppMessageState(
        icon: Icons.error_outline,
        title: 'Could not load the leaderboard',
        // A missing composite index is the likely cause on a fresh deploy and
        // its fix is a deploy, not a retry — so name it rather than showing a
        // bare Firestore string.
        subtitle: 'If this persists, the score index may still be building.\n'
            '$_error',
      );
    }
    if (_ranked.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ranked.isEmpty) {
      return AppMessageState(
        icon: Icons.leaderboard_outlined,
        title: 'No scores yet',
        subtitle: _assigned > 0
            ? '$_assigned candidate(s) are in this round but none has been '
                'scored yet.'
            : 'Scores appear here once candidates have taken this round.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: _ranked.length + 1,
        itemBuilder: (context, i) {
          if (i == _ranked.length) return _footer(theme);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LeaderboardRow(
              interview: _ranked[i],
              rank: i + 1,
            ),
          );
        },
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed: _loadMore,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry loading more'),
          ),
        ),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: const Text('Load more'),
          ),
        ),
      );
    }

    // Fully loaded, so the ranked count is exact and the gap can be stated
    // honestly. Without this the screen looks like the whole round.
    final unscored = _assigned >= 0 ? _assigned - _ranked.length : -1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            _assigned >= 0
                ? '${_ranked.length} of $_assigned candidate(s) scored'
                : '${_ranked.length} scored',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (unscored > 0) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _openAllCandidates,
              child: Text(
                  '$unscored not scored yet — view all candidates'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One ranked candidate. Collapsed it is rank + name + score; expanded it shows
/// why, including the raw résumé behind a second disclosure.
class _LeaderboardRow extends StatefulWidget {
  final Interview interview;
  final int rank;

  const _LeaderboardRow({required this.interview, required this.rank});

  @override
  State<_LeaderboardRow> createState() => _LeaderboardRowState();
}

class _LeaderboardRowState extends State<_LeaderboardRow> {
  bool _expanded = false;

  /// The raw text is opt-in INSIDE the expansion: it is thousands of characters
  /// and would bury the breakdown it is meant to support.
  bool _showRawText = false;

  Interview get _i => widget.interview;

  int? get _score => (_i.result?['overallScore'] as num?)?.toInt();

  ResumeSubmission? get _submission => ResumeSubmission.fromMap(_i.resume);

  String get _who =>
      (_i.candidateName?.trim().isNotEmpty == true)
          ? _i.candidateName!.trim()
          : _i.candidateEmail;

  Color _scoreColor(ThemeData theme) {
    final s = _score ?? 0;
    if (s >= 70) return theme.colorScheme.primary;
    if (s >= 45) return theme.colorScheme.secondary;
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final submission = _submission;
    final score = submission?.score;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              _rankBadge(theme),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_score ?? '—'}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _scoreColor(theme),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(ThemeData theme) {
    // The top three read as a podium; past that the number is just a position.
    final highlight = widget.rank <= 3;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        shape: BoxShape.circle,
        border: highlight
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Text('${widget.rank}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlight
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          )),
    );
  }

  Widget _detail(ThemeData theme, ResumeSubmission? submission) {
    final score = submission?.score;

    // Not a résumé round (or scoring never ran): fall back to whatever the
    // canonical result map holds, so an interview round still expands usefully.
    if (score == null) {
      final summary = (_i.result?['summary'] as String?)?.trim() ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.isNotEmpty)
            Text(summary, style: theme.textTheme.bodyMedium)
          else
            Text('No breakdown recorded for this candidate.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (submission != null) ...[
            const SizedBox(height: 12),
            _rawTextSection(theme, submission),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (score.summary.isNotEmpty)
          Text(score.summary, style: theme.textTheme.bodyMedium),
        if (score.skills.isNotEmpty) ...[
          const SizedBox(height: 14),
          _label(theme, 'Skills'),
          const SizedBox(height: 6),
          // Must-haves first, weakest evidence first — the recruiter is looking
          // for what is missing.
          ...score.skillsByConcern.map((s) => _skillRow(theme, s)),
        ],
        if (score.strengths.isNotEmpty) ...[
          const SizedBox(height: 14),
          _label(theme, 'Strengths'),
          const SizedBox(height: 4),
          ...score.strengths.map((s) => _bullet(theme, s, Icons.add, null)),
        ],
        if (score.gaps.isNotEmpty) ...[
          const SizedBox(height: 14),
          _label(theme, 'Gaps'),
          const SizedBox(height: 4),
          ...score.gaps.map((g) =>
              _bullet(theme, g, Icons.remove, theme.colorScheme.error)),
        ],
        if (submission != null) ...[
          const SizedBox(height: 14),
          _rawTextSection(theme, submission),
        ],
        if (score.model.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Scored by ${score.model}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic)),
        ],
      ],
    );
  }

  /// The raw résumé, behind a toggle. This is the point of storing the text: a
  /// recruiter can check the AI against the source instead of taking a number on
  /// trust.
  Widget _rawTextSection(ThemeData theme, ResumeSubmission submission) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _showRawText = !_showRawText),
              icon: Icon(
                  _showRawText ? Icons.visibility_off : Icons.visibility,
                  size: 16),
              label: Text(_showRawText
                  ? 'Hide résumé text'
                  : 'View résumé text'),
            ),
            if (_showRawText)
              IconButton(
                tooltip: 'Copy résumé text',
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () async {
                  // Resolved before the await: inside a State, reaching for
                  // `context` afterwards is the async-gap trap this widget was
                  // linted for.
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(
                      ClipboardData(text: submission.text));
                  if (!mounted) return;
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Résumé text copied.')));
                },
              ),
          ],
        ),
        if (_showRawText) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (submission.fileName != null) submission.fileName!,
                    '${submission.charCount} characters',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            // Bounded height with its own scroll: a résumé is thousands of
            // characters and would otherwise make one row taller than the list.
            constraints: const BoxConstraints(maxHeight: 260),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: theme.colorScheme.outlineVariant
                      .withValues(alpha: 0.4)),
            ),
            child: SingleChildScrollView(
              // Selectable so a recruiter can pull a phrase straight out of the
              // résumé they are checking.
              child: SelectableText(
                submission.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _label(ThemeData theme, String text) => Text(
        text.toUpperCase(),
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );

  Widget _skillRow(ThemeData theme, ResumeSkillScore skill) {
    final weak = skill.score < 45;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (skill.required)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.star,
                      size: 12, color: theme.colorScheme.primary),
                ),
              Expanded(
                child: Text(skill.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text('${skill.score}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: weak
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                  )),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: skill.score / 100,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: weak
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          if (skill.evidence.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(skill.evidence,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _bullet(ThemeData theme, String text, IconData icon, Color? color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 13, color: color ?? theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text, style: theme.textTheme.bodySmall)),
          ],
        ),
      );
}
