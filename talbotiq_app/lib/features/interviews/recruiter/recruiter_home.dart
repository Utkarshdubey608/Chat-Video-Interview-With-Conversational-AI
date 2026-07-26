// lib/features/interviews/recruiter/recruiter_home.dart
//
// Recruiter landing surface (the Home tab of RecruiterShell): the list of TESTS
// this recruiter created. Tapping a test opens TestCandidatesPage, which loads
// that test's candidates in pages.
//
// Why tests and not candidates: this screen used to stream every interview and
// group them client-side, so a recruiter with 1,000 candidates paid one enormous
// read and built 1,000 widgets before seeing anything. Tests now have their own
// `tests/{testId}` metadata docs (see TestSummary), so the dashboard reads a few
// dozen tiny documents and defers candidate reads until a test is opened.
//
// Tests created before that collection existed have no metadata doc, so the
// first load backfills them from the existing interviews (idempotent — see
// InterviewRepository.backfillTests). "Rebuild test list" in the app bar re-runs
// it on demand if anything ever drifts.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/utils/date_format.dart';
import 'package:talbotiq/shared/widgets/app_message_state.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/models/test_summary.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/interviews/recruiter/create_interview_page.dart';
import 'package:talbotiq/features/interviews/recruiter/test_candidates_page.dart';

class RecruiterHome extends StatefulWidget {
  const RecruiterHome({super.key});

  @override
  State<RecruiterHome> createState() => _RecruiterHomeState();
}

class _RecruiterHomeState extends State<RecruiterHome> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  final List<TestSummary> _tests = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _backfilling = false;
  Object? _error;

  /// Guards the automatic backfill so an empty-but-legitimate account doesn't
  /// re-scan its interviews on every page load.
  bool _triedBackfill = false;

  String _query = '';
  Timer? _debounce;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

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
    if (remaining < 300) _loadMore();
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = raw.trim());
    });
  }

  Future<void> _refresh({bool allowBackfill = true}) async {
    setState(() {
      _tests.clear();
      _cursor = null;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
    if (!mounted) return;

    // No metadata docs but interviews exist => tests predate this collection.
    // Backfill once, then reload.
    if (allowBackfill && _tests.isEmpty && !_triedBackfill) {
      _triedBackfill = true;
      await _runBackfill(silent: true);
    }
  }

  Future<void> _runBackfill({bool silent = false}) async {
    if (_backfilling) return;
    setState(() => _backfilling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n =
          await context.read<InterviewRepository>().backfillTests(_uid);
      if (!mounted) return;
      setState(() => _backfilling = false);
      if (n > 0) {
        await _refresh(allowBackfill: false);
        if (!silent && mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('$n test(s) found.')),
          );
        }
      } else if (!silent) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nothing to rebuild.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _backfilling = false);
      if (!silent) {
        messenger.showSnackBar(SnackBar(content: Text('Rebuild failed: $e')));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await context
          .read<InterviewRepository>()
          .fetchTestsPage(recruiterId: _uid, startAfter: _cursor);
      if (!mounted) return;
      setState(() {
        _tests.addAll(page.items);
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

  /// Tests are few, so title filtering over the loaded pages is enough — no
  /// server-side search needed at this level.
  List<TestSummary> get _visible {
    if (_query.isEmpty) return _tests;
    final q = _query.toLowerCase();
    return _tests.where((t) => t.title.toLowerCase().contains(q)).toList();
  }

  void _create() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CreateInterviewPage()))
        .then((_) {
      // A newly created test needs to appear without a manual pull-to-refresh.
      if (mounted) _refresh(allowBackfill: false);
    });
  }

  void _open(TestSummary t) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TestCandidatesPage(test: t)))
        // Counts may have changed (publish, delete), so re-read on return.
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const _Wordmark(subtitle: 'Recruiter'),
        actions: [
          IconButton(
            tooltip: 'Rebuild test list',
            icon: _backfilling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: _backfilling ? null : () => _runBackfill(),
          ),
          const LogoutButton(),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Create interview'),
      ),
      body: Column(
        children: [
          if (_tests.isNotEmpty) _searchBar(),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search tests by name',
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
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null && _tests.isEmpty) {
      return AppMessageState(
        icon: Icons.error_outline,
        title: 'Could not load tests',
        subtitle: '$_error',
      );
    }
    if (_tests.isEmpty && (_loading || _backfilling)) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _visible;
    if (items.isEmpty) {
      return AppMessageState(
        icon: _query.isEmpty ? Icons.inbox_outlined : Icons.search_off,
        title: _query.isEmpty ? 'No interviews yet' : 'No matching tests',
        subtitle: _query.isEmpty
            ? 'Create one and assign it to a candidate email.'
            : 'Try a different name.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(allowBackfill: false),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == items.length) return _pagerRow(theme);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TestRow(test: items[index], onTap: () => _open(items[index])),
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
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (!_hasMore) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: TextButton(
            onPressed: _loadMore, child: const Text('Load more tests')),
      ),
    );
  }
}

/// One test row. Candidate/completed totals come from count() aggregates rather
/// than from loading the test's interviews, so the dashboard never reads
/// candidate documents.
class _TestRow extends StatefulWidget {
  final TestSummary test;
  final VoidCallback onTap;
  const _TestRow({required this.test, required this.onTap});

  @override
  State<_TestRow> createState() => _TestRowState();
}

class _TestRowState extends State<_TestRow> {
  int _total = -1;
  int _completed = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<InterviewRepository>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final total = await repo.countForRecruiter(
        recruiterId: uid, testId: widget.test.testId);
    final done = await repo.countForRecruiter(
        recruiterId: uid,
        testId: widget.test.testId,
        status: InterviewStatus.completed);
    if (!mounted) return;
    setState(() {
      _total = total;
      _completed = done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.test;
    final icon = switch (t.type) {
      InterviewType.video => Icons.videocam_outlined,
      InterviewType.voice => Icons.record_voice_over_outlined,
      InterviewType.chat => Icons.chat_bubble_outline,
    };
    final counts = _total < 0
        ? 'Loading…'
        : '$_total candidate(s)'
            '${_completed >= 0 ? ' · $_completed completed' : ''}';

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(counts, style: theme.textTheme.bodySmall),
                    if (t.createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(formatDateTime(t.createdAt!),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final String subtitle;
  const _Wordmark({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
            children: [
              const TextSpan(text: 'talbot'),
              TextSpan(
                  text: 'iq',
                  style: TextStyle(color: theme.colorScheme.primary)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('· $subtitle',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
