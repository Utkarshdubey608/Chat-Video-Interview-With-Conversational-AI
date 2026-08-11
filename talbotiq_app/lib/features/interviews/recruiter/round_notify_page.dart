// lib/features/interviews/recruiter/round_notify_page.dart
//
// After a round closes: choose who advances, and tell them.
//
// The shortlist is PRE-SELECTED from the round's own `advance` policy — the bar
// the recruiter wrote down when they designed the round — and then made fully
// editable. Pre-selecting saves the work; keeping it editable matters because a
// score is a screening signal, not a decision, and the recruiter is the one
// accountable for the outcome.
//
// Only SCORED candidates appear. Someone who never submitted has no score to
// judge, and mailing them "you did not advance" for a round they never took is a
// worse mistake than saying nothing — the footer says how many were left out.
//
// Two separate sends, never one: the shortlist mail and the not-advancing mail go
// to disjoint groups with different templates, and each is confirmed on its own.
// Nothing is sent by merely opening this screen.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/models/interview_round.dart';
import 'package:talbotiq/features/interviews/models/test_summary.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/mailer/services/mailer_service.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';
import 'package:talbotiq/shared/widgets/app_message_state.dart';

/// Built-in templates for the two outcomes (see backend `app/templating.py`).
const String kShortlistTemplateId = 'builtin:round_shortlist';
const String kNotAdvancingTemplateId = 'builtin:round_not_advancing';

/// Who [round]'s own advance rule would shortlist out of [ranked] (best first).
///
/// Public and pure so it can be tested without a widget tree: this decides whose
/// name is pre-ticked on a screen that sends rejection emails, and an off-by-one
/// here is a person wrongly told they did not get through.
///
/// `manual` returns nothing deliberately — the recruiter said they would pick, so
/// pre-ticking names would be putting words in their mouth.
List<Interview> shortlistFor(InterviewRound round, List<Interview> ranked) {
  final advance = round.advance;
  switch (advance.mode) {
    case AdvanceMode.manual:
      return const [];
    case AdvanceMode.topN:
      final n = (advance.value ?? 0).round();
      if (n <= 0) return const [];
      // `take` already clamps to the list length, so a top-20 rule on 5
      // candidates selects all 5 rather than throwing.
      return ranked.take(n).toList();
    case AdvanceMode.threshold:
      final bar = advance.value;
      if (bar == null) return const [];
      return ranked
          .where((i) => ((i.result?['overallScore'] as num?) ?? -1) >= bar)
          .toList();
  }
}

class RoundNotifyPage extends StatefulWidget {
  final TestSummary test;
  final InterviewRound round;

  /// The round that follows, used only to name it in the shortlist email.
  final InterviewRound? nextRound;

  const RoundNotifyPage({
    super.key,
    required this.test,
    required this.round,
    this.nextRound,
  });

  @override
  State<RoundNotifyPage> createState() => _RoundNotifyPageState();
}

class _RoundNotifyPageState extends State<RoundNotifyPage> {
  /// Ranked, scored candidates. Loaded once — this is a decision screen, and a
  /// live stream reshuffling rows under a half-made selection would be hostile.
  final List<Interview> _ranked = [];

  /// Interview ids the recruiter is advancing.
  final Set<String> _selected = {};

  bool _loading = true;
  bool _sending = false;
  Object? _error;

  /// Everyone in the round, scored or not, so the gap can be reported.
  int _assigned = -1;

  final _mailer = MailerService();

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _recruiterEmail =>
      FirebaseAuth.instance.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<InterviewRepository>();
    try {
      // One generous page: this is a shortlist decision, not a browsing screen.
      // The footer says so when there are more.
      final page = await repo.fetchLeaderboardPage(
        recruiterId: _uid,
        testId: widget.test.testId,
        roundId: widget.round.id,
        limit: 200,
      );
      final assigned = await repo.countForRecruiter(
        recruiterId: _uid,
        testId: widget.test.testId,
        roundId: widget.round.id,
      );
      if (!mounted) return;
      setState(() {
        _ranked
          ..clear()
          ..addAll(page.items);
        _selected
          ..clear()
          ..addAll(shortlistFor(widget.round, page.items).map((i) => i.id));
        _assigned = assigned;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String get _preselectExplanation {
    final advance = widget.round.advance;
    switch (advance.mode) {
      case AdvanceMode.manual:
        return 'This round advances candidates manually, so nobody is '
            'pre-selected. Tick whoever moves on.';
      case AdvanceMode.topN:
        return 'Pre-selected: the top ${(advance.value ?? 0).round()} by score, '
            'from this round\'s advance rule. Change it however you like.';
      case AdvanceMode.threshold:
        return 'Pre-selected: everyone scoring ${(advance.value ?? 0).round()} '
            'or above, from this round\'s advance rule. Change it however you '
            'like.';
    }
  }

  List<Interview> get _shortlisted =>
      _ranked.where((i) => _selected.contains(i.id)).toList();
  List<Interview> get _others =>
      _ranked.where((i) => !_selected.contains(i.id)).toList();

  // ── Sending ───────────────────────────────────────────────────────────────

  Future<void> _send({
    required List<Interview> group,
    required String templateId,
    required String what,
  }) async {
    if (_sending || group.isEmpty) return;

    if (!_mailer.isConfigured) {
      _toast('No mail server is configured, so nothing can be sent.');
      return;
    }
    if (_recruiterEmail.isEmpty) {
      _toast('Your account has no email address, so mail cannot be sent.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Email ${group.length} candidate(s)?'),
        content: Text(
          'This sends the "$what" email now. It cannot be unsent, so check the '
          'selection first.\n\n'
          'To: ${group.take(3).map((i) => i.candidateEmail).join(', ')}'
          '${group.length > 3 ? ' and ${group.length - 3} more' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final report = await _mailer.send(
        ownerEmail: _recruiterEmail,
        templateId: templateId,
        // candidate_name / candidate_email are filled per recipient by the
        // backend; everything else is the same for the whole group.
        sharedContext: {
          'interview_title': widget.test.title,
          'round_title': widget.round.title,
          'next_round': widget.nextRound?.title ?? 'the next round',
          'recruiter_name': _recruiterDisplayName,
          'company': _recruiterDisplayName,
        },
        recipients: [
          for (final i in group)
            MailRecipient(email: i.candidateEmail, name: i.candidateName),
        ],
      );
      if (!mounted) return;
      setState(() => _sending = false);
      // Report the real outcome. Two ways this could otherwise read as a
      // success it was not: a partial failure, and DRY_RUN — which the backend
      // defaults to ON, logging the mail instead of delivering it. Telling a
      // recruiter their rejections went out when nothing left the building is
      // the worst possible thing to get wrong here.
      if (report.provider == 'dry_run') {
        _toast('Nothing was actually sent: the mail server is in dry-run mode. '
            '${report.total} email(s) were logged on the server only.');
      } else if (report.failed == 0) {
        _toast('Sent to ${report.sent} candidate(s).');
      } else {
        _toast('Sent ${report.sent}, failed ${report.failed}. '
            'Check the addresses and try the failures again.');
      }
    } on MailerException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('Could not send: $e');
    }
  }

  String get _recruiterDisplayName {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email ?? '';
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : 'the recruiter';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notify candidates'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.test.title} · ${widget.round.title}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: _body(theme),
      bottomNavigationBar: _loading || _ranked.isEmpty ? null : _actions(theme),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppMessageState(
        icon: Icons.error_outline,
        title: 'Could not load the candidates',
        subtitle: '$_error',
      );
    }
    if (_ranked.isEmpty) {
      return AppMessageState(
        icon: Icons.mail_outline,
        title: 'Nobody to notify',
        subtitle: _assigned > 0
            ? '$_assigned candidate(s) are in this round but none has a score, '
                'so there is nothing to decide on yet.'
            : 'This round has no scored candidates.',
      );
    }

    final unscored = _assigned >= 0 ? _assigned - _ranked.length : 0;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _ranked.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _explainer(theme, unscored);
        if (index == _ranked.length + 1) return _footer(theme, unscored);
        final i = _ranked[index - 1];
        return _candidateRow(theme, i, index);
      },
    );
  }

  Widget _explainer(ThemeData theme, int unscored) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: RecruiterPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rule, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${_selected.length} of ${_ranked.length} '
                        'advancing',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: _sending
                        ? null
                        : () => setState(() {
                              if (_selected.length == _ranked.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(_ranked.map((i) => i.id));
                              }
                            }),
                    child: Text(_selected.length == _ranked.length
                        ? 'Clear all'
                        : 'Select all'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_preselectExplanation,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (unscored > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$unscored candidate(s) in this round have no score and are '
                  'not listed — they will not be emailed either way.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _candidateRow(ThemeData theme, Interview i, int rank) {
    final selected = _selected.contains(i.id);
    final score = (i.result?['overallScore'] as num?)?.toInt();
    final who = (i.candidateName?.trim().isNotEmpty == true)
        ? i.candidateName!.trim()
        : i.candidateEmail;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RecruiterPanel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: CheckboxListTile(
          value: selected,
          onChanged: _sending
              ? null
              : (v) => setState(() {
                    if (v == true) {
                      _selected.add(i.id);
                    } else {
                      _selected.remove(i.id);
                    }
                  }),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '#$rank · ${i.candidateEmail}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          secondary: Text(
            '${score ?? '—'}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme, int unscored) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _assigned >= 0
              ? '${_ranked.length} scored of $_assigned in this round'
              : '${_ranked.length} scored',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );

  Widget _actions(ThemeData theme) {
    final shortlisted = _shortlisted.length;
    final others = _others.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sending)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_sending || shortlisted == 0)
                        ? null
                        : () => _send(
                              group: _shortlisted,
                              templateId: kShortlistTemplateId,
                              what: 'moving to the next round',
                            ),
                    icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                    label: Text('Email shortlist ($shortlisted)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_sending || others == 0)
                        ? null
                        : () => _send(
                              group: _others,
                              templateId: kNotAdvancingTemplateId,
                              what: 'not advancing',
                            ),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: Text('Email others ($others)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Two separate emails. Sending one does not send the other.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
