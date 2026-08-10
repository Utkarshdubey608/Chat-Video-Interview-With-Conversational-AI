// lib/features/interviews/recruiter/test_candidates_page.dart
//
// The candidates of ONE test, loaded in pages.
//
// The dashboard lists tests (a few dozen tiny docs); opening one lands here and
// only then are that test's candidates read — scoped by `testId` and fetched
// 25 at a time. That keeps a 1,000-candidate test off the dashboard's critical
// path entirely, and means this screen's cost is bounded by what's on screen
// rather than by how many people took the test.
//
// Search runs SERVER-side as a candidateEmailLower prefix range (so a match
// deep in the test is found without paging to it) and is additionally narrowed
// client-side over loaded rows, which is the only way to match partial NAMES —
// Firestore range queries do prefixes, never substrings.
//
// Header counts come from count() aggregates, so "312 candidates · 180
// completed" stays true while only a page is in memory.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/utils/date_format.dart';
import 'package:talbotiq/shared/widgets/app_message_state.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/models/test_summary.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/interviews/recruiter/create_interview_page.dart';
import 'package:talbotiq/features/interviews/recruiter/evaluate_interview_page.dart';

class TestCandidatesPage extends StatefulWidget {
  final TestSummary test;
  const TestCandidatesPage({super.key, required this.test});

  @override
  State<TestCandidatesPage> createState() => _TestCandidatesPageState();
}

class _TestCandidatesPageState extends State<TestCandidatesPage> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  final List<Interview> _loaded = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  String _query = '';
  Timer? _debounce;

  int _total = -1;
  int _completed = -1;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _testId => widget.test.testId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || !_hasMore) return;
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) _loadMore();
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = raw.trim();
      if (q == _query) return;
      _query = q;
      _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loaded.clear();
      _cursor = null;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
    await _loadCounts();
  }

  Future<void> _loadCounts() async {
    final repo = context.read<InterviewRepository>();
    final total =
        await repo.countForRecruiter(recruiterId: _uid, testId: _testId);
    final done = await repo.countForRecruiter(
        recruiterId: _uid,
        testId: _testId,
        status: InterviewStatus.completed);
    if (!mounted) return;
    setState(() {
      _total = total;
      _completed = done;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await context.read<InterviewRepository>().fetchRecruiterPage(
            recruiterId: _uid,
            testId: _testId,
            startAfter: _cursor,
            emailPrefix: _looksLikeEmailPrefix(_query) ? _query : null,
          );
      if (!mounted) return;
      setState(() {
        _loaded.addAll(page.items);
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

  static bool _looksLikeEmailPrefix(String q) {
    if (q.length < 2 || q.contains(' ')) return false;
    return RegExp(r'^[a-zA-Z0-9._%+\-@]+$').hasMatch(q);
  }

  List<Interview> get _visible {
    if (_query.isEmpty) return _loaded;
    final q = _query.toLowerCase();
    return _loaded.where((i) {
      final name = (i.candidateName ?? '').toLowerCase();
      return name.contains(q) || i.candidateEmail.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _publishAll() async {
    final repo = context.read<InterviewRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End test and publish results?'),
        content: Text(
          'Every candidate of "${widget.test.title}" who completed the '
          'interview will be able to see their result. This affects all '
          'completed candidates, not just the ones loaded here.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Publish')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Publishes server-side across the whole test, independent of what this
      // screen has loaded.
      await repo.publishTest(_testId, _uid);
      if (!mounted) return;
      await _refresh();
      messenger.showSnackBar(
          const SnackBar(content: Text('Results published to candidates.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not publish: $e')));
    }
  }

  /// Deletes the whole test and every candidate's data for it.
  ///
  /// Irreversible and bulk, so it requires typing DELETE rather than a single
  /// tap — a mis-tap here would wipe every response for the test.
  Future<void> _confirmDeleteTest() async {
    final repo = context.read<InterviewRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteTestDialog(
        title: widget.test.title,
        countLabel: _total >= 0 ? '$_total candidate(s)' : 'every candidate',
      ),
    );
    if (ok != true) return;

    try {
      final n = await repo.deleteTest(_testId, _uid);
      if (!mounted) return;
      // Nothing left to show — return to the dashboard.
      navigator.pop();
      messenger.showSnackBar(SnackBar(
          content: Text('Test deleted ($n candidate record(s) removed).')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.test.title),
        actions: [
          if (_completed > 0)
            IconButton(
              tooltip: 'End test & publish results',
              icon: const Icon(Icons.publish_outlined),
              onPressed: _publishAll,
            ),
          PopupMenuButton<String>(
            tooltip: 'Test actions',
            onSelected: (v) {
              if (v == 'delete') _confirmDeleteTest();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_outlined,
                        size: 18, color: Theme.of(ctx).colorScheme.error),
                    const SizedBox(width: 10),
                    const Text('Delete entire test'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _header(theme),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final shown = _visible.length;
    final label = _query.isNotEmpty
        ? '$shown match${shown == 1 ? '' : 'es'}'
        : _total >= 0
            ? 'Showing $shown of $_total candidate(s)'
                '${_completed >= 0 ? ' · $_completed completed' : ''}'
            : '$shown candidate(s)';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search this test by name or email',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null && _loaded.isEmpty) {
      return AppMessageState(
        icon: Icons.error_outline,
        title: 'Could not load candidates',
        subtitle: '$_error',
      );
    }
    if (_loaded.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _visible;
    if (items.isEmpty) {
      return AppMessageState(
        icon: _query.isEmpty ? Icons.people_outline : Icons.search_off,
        title: _query.isEmpty
            ? 'No candidates in this test'
            : 'No matching candidates',
        subtitle: _query.isEmpty
            ? 'Assign this test to a candidate email to get started.'
            : 'Try a different name or email.',
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == items.length) return _pagerRow(theme);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _InterviewCard(
              interview: items[index],
              groupInterviews: items,
              index: index,
            ),
          );
        },
      ),
    );
  }

  Widget _pagerRow(ThemeData theme) {
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
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('End of list',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: TextButton(
          onPressed: _loadMore,
          child: const Text('Load more candidates'),
        ),
      ),
    );
  }
}

class _InterviewCard extends StatelessWidget {
  final Interview interview;
  final List<Interview> groupInterviews;
  final int index;

  const _InterviewCard({
    required this.interview,
    required this.groupInterviews,
    required this.index,
  });

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDetailBadge(
      BuildContext context, String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100), // Pill shape!
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = interview.candidateName?.isNotEmpty == true
        ? interview.candidateName!
        : interview.candidateEmail;
    final hasName = interview.candidateName?.isNotEmpty == true;

    final subtitleText = hasName
        ? '${interview.candidateEmail} · ${interview.questions.length} Qs'
        : '${interview.questions.length} Qs';

    final score = interview.result != null ? interview.result!['overallScore'] : null;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28.0), // More rounded!
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(28.0), // More rounded!
        onTap: () => _showDetail(context, interview),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle, // Circular shape!
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'C',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusChip(status: interview.status),
                  if (score != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(100), // Pill shape!
                      ),
                      child: Text(
                        'Score: $score',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Interview initialInterview) {
    final theme = Theme.of(context);
    int activeIndex = index;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setStateSheet) {
          final i = groupInterviews[activeIndex];
          final completed = i.status == InterviewStatus.completed;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Candidate Navigation Header
                  if (groupInterviews.length > 1) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                          onPressed: activeIndex > 0
                              ? () => setStateSheet(() => activeIndex--)
                              : null,
                        ),
                        Text(
                          'Candidate ${activeIndex + 1} of ${groupInterviews.length}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                          onPressed: activeIndex < groupInterviews.length - 1
                              ? () => setStateSheet(() => activeIndex++)
                              : null,
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                  ],
                  Text(i.title,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildDetailBadge(
                        sheetContext,
                        i.type.label,
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                        theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      _buildDetailBadge(
                        sheetContext,
                        i.status.label,
                        theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
                        theme.colorScheme.secondary,
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  if (i.candidateName?.isNotEmpty == true)
                    _kv(sheetContext, 'Name', i.candidateName!),
                  _kv(sheetContext, 'Email', i.candidateEmail),
                  _kv(sheetContext, 'Duration', '${i.durationMinutes} min'),
                  _kv(sheetContext, 'Attempts',
                      i.maxAttempts == null ? 'Unlimited' : '${i.attemptsUsed}/${i.maxAttempts}'),
                  if (i.availableFrom != null)
                    _kv(sheetContext, 'From', formatDateTime(i.availableFrom!)),
                  if (i.expiresAt != null)
                    _kv(sheetContext, 'Expires',
                        '${formatDateTime(i.expiresAt!)}${i.isExpired ? '  (expired)' : ''}'),
                  _kv(
                      sheetContext,
                      'Result Status',
                      i.status != InterviewStatus.completed
                          ? 'Not taken yet'
                          : (i.result == null ||
                                  (i.result!['evaluatedBy'] as String? ?? '')
                                      .isEmpty)
                              // No score yet — either AI scoring hasn't landed
                              // (see candidate_video_shell.dart's placeholder
                              // result) or nobody has evaluated it manually.
                              ? 'Awaiting evaluation'
                              : i.resultPublished
                                  ? 'Published'
                                  : 'Draft — not published'),
                  if (i.result != null && i.result!['overallScore'] != null)
                    _kv(sheetContext, 'Overall Score', '${i.result!['overallScore']}/100'),
                  const Divider(height: 24),
                  Text('Prompt', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20), // More rounded!
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      i.prompt.isEmpty ? 'No custom prompt configured.' : i.prompt,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Questions', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20), // More rounded!
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: i.questions.isEmpty
                          ? [Text('No questions configured.', style: theme.textTheme.bodyMedium)]
                          : i.questions.asMap().entries.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${e.key + 1}. ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          e.value,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (completed)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => EvaluateInterviewPage(
                              interview: i,
                              groupInterviews: groupInterviews,
                              initialIndex: activeIndex,
                            ),
                          ));
                        },
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: Text(i.resultPublished
                            ? 'Review / edit result'
                            : 'Evaluate & publish'),
                      ),
                    ),
                  if (i.result != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100)),
                        ),
                        // Clears the answers/report but keeps the candidate
                        // assigned, so they can retake — unlike "Delete", which
                        // removes them from the test entirely.
                        onPressed: () => _confirmClearResult(context, i),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Delete response (allow retake)'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => CreateInterviewPage(existing: i),
                              ));
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmDelete(context, i),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                              side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  /// Wipes this candidate's answers + AI report and returns them to "assigned"
  /// so they can sit the test again. Keeps the assignment itself.
  Future<void> _confirmClearResult(BuildContext context, Interview i) async {
    final repo = context.read<InterviewRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final name = i.candidateName?.trim().isNotEmpty == true
        ? i.candidateName!.trim()
        : i.candidateEmail;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this response?'),
        content: Text(
          "$name's answers and AI report for this test will be permanently "
          'deleted, and they will be able to take it again. The assignment '
          'itself is kept.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete response',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.clearResult(i.id);
      if (context.mounted) Navigator.pop(context); // close the detail sheet
      messenger.showSnackBar(
          const SnackBar(content: Text('Response deleted; candidate can retake.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, Interview i) async {
    final repo = context.read<InterviewRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove candidate from test?'),
        content: Text(
          'This deletes the assignment AND any response for “${i.title}”. '
          'The candidate will no longer see this test at all. To wipe only '
          'their answers and let them retake, use "Delete response" instead.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await repo.delete(i.id);
    if (context.mounted) Navigator.pop(context); // close the detail sheet
  }
}

class _StatusChip extends StatelessWidget {
  final InterviewStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color bg;
    switch (status) {
      case InterviewStatus.completed:
        bg = Colors.green;
        break;
      case InterviewStatus.inProgress:
        bg = Colors.orange;
        break;
      case InterviewStatus.assigned:
        bg = theme.colorScheme.outline;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100), // Pill-shaped!
      ),
      child: Text(
        status.label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: bg),
      ),
    );
  }
}

/// Type-to-confirm dialog for deleting an entire test.
///
/// A StatefulWidget rather than a `StatefulBuilder` + local controller so the
/// TextEditingController's lifetime matches the dialog's. The previous version
/// called `ctrl.dispose()` on the line after `showDialog` returned — which is
/// BEFORE the dialog's exit transition finishes, so the still-mounted TextField
/// was left holding a disposed controller. That surfaced as a framework
/// assertion (`_dependents.isEmpty`) rather than anything that pointed here.
///
/// The content also scrolls: `autofocus: true` raises the keyboard immediately,
/// and an AlertDialog does not scroll its content by default, so on a phone the
/// column had nowhere to go.
class _DeleteTestDialog extends StatefulWidget {
  const _DeleteTestDialog({required this.title, required this.countLabel});

  final String title;
  final String countLabel;

  @override
  State<_DeleteTestDialog> createState() => _DeleteTestDialogState();
}

class _DeleteTestDialogState extends State<_DeleteTestDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Rebuilds to enable/disable the destructive action as they type.
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _confirmed => _controller.text.trim().toUpperCase() == 'DELETE';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Delete entire test?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently deletes "${widget.title}" and the assignments, '
              'answers and AI reports of ${widget.countLabel} who took it. '
              'This cannot be undone.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Type DELETE to confirm',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(isDense: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_confirmed) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          child: Text(
            'Delete test',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}
