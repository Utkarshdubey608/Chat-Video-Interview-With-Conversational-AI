// lib/features/interviews/recruiter/recruiter_home.dart
//
// Recruiter landing surface: lists the interviews this recruiter created
// (video + chat), with status/result, and a Create button. Also exposes
// Settings (API keys) and a "sync keys to cloud" action so candidate devices
// can pull them (see AppConfigService).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_format.dart';
import '../../../providers/app_store.dart';
import '../../../views/settings_page.dart';
import '../../app_config/app_config_service.dart';
import '../../auth/auth_service.dart';
import '../../recruiter/analytics/analytics_page.dart';
import '../../../widgets/app_message_state.dart';
import '../models/interview.dart';
import '../services/interview_repository.dart';
import 'create_interview_page.dart';
import 'evaluate_interview_page.dart';

class RecruiterHome extends StatelessWidget {
  const RecruiterHome({super.key});

  Future<void> _syncKeys(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await context
          .read<AppConfigService>()
          .pushForRecruiter(uid, context.read<AppStore>());
      messenger.showSnackBar(
        const SnackBar(content: Text('API keys synced to cloud.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _SettingsScaffold()),
    );
  }

  void _create(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateInterviewPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.read<InterviewRepository>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const _Wordmark(subtitle: 'Recruiter'),
        actions: [
          IconButton(
            tooltip: 'Analytics',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AnalyticsPage()),
            ),
          ),
          IconButton(
            tooltip: 'Sync API keys to cloud',
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: () => _syncKeys(context),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('Create interview'),
      ),
      body: StreamBuilder<List<Interview>>(
        stream: repo.watchForRecruiter(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return AppMessageState(
              icon: Icons.error_outline,
              title: 'Could not load interviews',
              subtitle: '${snap.error}',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          if (all.isEmpty) {
            return const AppMessageState(
              icon: Icons.inbox_outlined,
              title: 'No interviews yet',
              subtitle: 'Create one and assign it to a candidate email.',
            );
          }
          // Group candidates by their shared test (created together).
          final groups = <String, List<Interview>>{};
          for (final i in all) {
            final key = i.testId.isNotEmpty ? i.testId : i.id;
            groups.putIfAbsent(key, () => []).add(i);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              for (final entry in groups.entries)
                _TestSection(testId: entry.key, interviews: entry.value),
            ],
          );
        },
      ),
    );
  }
}

/// Wraps the reused [SettingsPage] in its own Scaffold (it has no app bar).
class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SettingsPage(),
    );
  }
}

class _InterviewCard extends StatelessWidget {
  final Interview interview;
  const _InterviewCard({required this.interview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final IconData typeIcon = switch (interview.type) {
      InterviewType.video => Icons.videocam_outlined,
      InterviewType.voice => Icons.record_voice_over_outlined,
      InterviewType.chat => Icons.chat_bubble_outline,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            typeIcon,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(interview.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${interview.candidateEmail}\n${interview.questions.length} question(s)',
        ),
        isThreeLine: true,
        trailing: _StatusChip(status: interview.status),
        onTap: () => _showDetail(context, interview),
      ),
    );
  }

  void _showDetail(BuildContext context, Interview i) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i.title,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('${i.type.label} · ${i.status.label}'),
              const SizedBox(height: 16),
              _kv(context, 'Candidate', i.candidateEmail),
              _kv(context, 'Duration', '${i.durationMinutes} min'),
              _kv(context, 'Attempts',
                  i.maxAttempts == null ? 'Unlimited' : '${i.attemptsUsed}/${i.maxAttempts}'),
              if (i.availableFrom != null)
                _kv(context, 'From', formatDateTime(i.availableFrom!)),
              if (i.expiresAt != null)
                _kv(context, 'Expires',
                    '${formatDateTime(i.expiresAt!)}${i.isExpired ? '  (expired)' : ''}'),
              const SizedBox(height: 12),
              Text('Prompt', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(i.prompt.isEmpty ? '—' : i.prompt),
              const SizedBox(height: 12),
              Text('Questions',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              ...i.questions.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${e.key + 1}. ${e.value}'),
                    ),
                  ),
              _kv(
                  context,
                  'Result',
                  i.status != InterviewStatus.completed
                      ? 'Not taken yet'
                      : i.result == null
                          ? 'Awaiting evaluation'
                          : i.resultPublished
                              ? 'Published (score ${i.result!['overallScore'] ?? '—'})'
                              : 'Draft — not published'),
              const SizedBox(height: 16),
              if (i.status == InterviewStatus.completed)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EvaluateInterviewPage(interview: i),
                      ));
                    },
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(i.resultPublished
                        ? 'Review / edit result'
                        : 'Evaluate & publish'),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CreateInterviewPage(existing: i),
                        ));
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDelete(context, i),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Interview i) async {
    final repo = context.read<InterviewRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete interview?'),
        content: Text('“${i.title}” will be removed for the candidate too.'),
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

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 90,
                child: Text(k,
                    style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(v)),
          ],
        ),
      );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: bg),
      ),
    );
  }
}

/// One test = the group of candidates created together. Shows the config and a
/// batch "Publish results" (end test) that releases every candidate at once.
class _TestSection extends StatelessWidget {
  final String testId;
  final List<Interview> interviews;
  const _TestSection({required this.testId, required this.interviews});

  Future<void> _publishAll(BuildContext context) async {
    final repo = context.read<InterviewRepository>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish results?'),
        content: const Text(
            'This releases results to every candidate of this test who has an evaluated result.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.publishTest(testId, uid);
      messenger.showSnackBar(
          const SnackBar(content: Text('Results published to candidates.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Publish failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = interviews.first;
    final IconData typeIcon = switch (first.type) {
      InterviewType.video => Icons.videocam_outlined,
      InterviewType.voice => Icons.record_voice_over_outlined,
      InterviewType.chat => Icons.chat_bubble_outline,
    };
    final completed = interviews
        .where((i) => i.status == InterviewStatus.completed)
        .length;
    final publishable = interviews.any((i) =>
        i.status == InterviewStatus.completed &&
        i.result != null &&
        !i.resultPublished);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(
              children: [
                Icon(typeIcon,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                          '${interviews.length} candidate(s) · $completed completed',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (publishable)
                  FilledButton.icon(
                    onPressed: () => _publishAll(context),
                    icon: const Icon(Icons.publish, size: 18),
                    label: const Text('Publish'),
                  ),
              ],
            ),
          ),
          ...interviews.map((i) => _InterviewCard(interview: i)),
        ],
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
