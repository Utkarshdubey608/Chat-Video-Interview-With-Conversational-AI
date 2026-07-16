// lib/features/interviews/recruiter/recruiter_home.dart
//
// Recruiter landing surface (the Home tab of RecruiterShell): lists the
// interviews this recruiter created (video + chat), with status/result, and a
// Create button. Analytics, Settings and the "sync keys to cloud" action now
// live under the shell's bottom navigation / Settings page — this app bar keeps
// only Sign out.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/utils/date_format.dart';
import 'package:talbotiq/shared/widgets/app_message_state.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/interviews/recruiter/create_interview_page.dart';
import 'package:talbotiq/features/interviews/recruiter/evaluate_interview_page.dart';

class RecruiterHome extends StatelessWidget {
  const RecruiterHome({super.key});

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
        actions: const [
          LogoutButton(),
          SizedBox(width: 4),
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
                          : i.result == null
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
                      color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
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
                      color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
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

class _TestSection extends StatefulWidget {
  final String testId;
  final List<Interview> interviews;
  const _TestSection({required this.testId, required this.interviews});

  @override
  State<_TestSection> createState() => _TestSectionState();
}

class _TestSectionState extends State<_TestSection> {
  String _searchQuery = '';
  int _displayLimit = 5;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      await repo.publishTest(widget.testId, uid);
      messenger.showSnackBar(
          const SnackBar(content: Text('Results published to candidates.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Publish failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = widget.interviews.first;
    final IconData typeIcon = switch (first.type) {
      InterviewType.video => Icons.videocam_outlined,
      InterviewType.voice => Icons.record_voice_over_outlined,
      InterviewType.chat => Icons.chat_bubble_outline,
    };
    final completed = widget.interviews
        .where((i) => i.status == InterviewStatus.completed)
        .length;
    final publishable = widget.interviews.any((i) =>
        i.status == InterviewStatus.completed &&
        i.result != null &&
        !i.resultPublished);

    // Filter candidates based on name / email
    final filtered = widget.interviews.where((i) {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) return true;
      final name = i.candidateName?.toLowerCase() ?? '';
      final email = i.candidateEmail.toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(32), // More rounded outer container!
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle, // Circular shape!
                  ),
                  child: Icon(
                    typeIcon,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                          '${widget.interviews.length} candidate(s) · $completed completed',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (publishable)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    ),
                    onPressed: () => _publishAll(context),
                    icon: const Icon(Icons.publish, size: 16),
                    label: const Text('Publish', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          
          // Render search bar if candidates count is high (e.g. > 5)
          if (widget.interviews.length > 5) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _displayLimit = 5; // Reset limit when searching
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search candidate name or email...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _displayLimit = 5;
                            });
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  fillColor: theme.colorScheme.surface,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ],

          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 36, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text(
                      'No matching candidates found',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            for (int idx = 0; idx < filtered.length && idx < _displayLimit; idx++) ...[
              _InterviewCard(
                interview: filtered[idx],
                groupInterviews: filtered,
                index: idx,
              ),
              if (idx < filtered.length - 1 && idx < _displayLimit - 1)
                const SizedBox(height: 8),
            ],
            if (filtered.length > _displayLimit || _displayLimit > 5) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (filtered.length > _displayLimit)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                        foregroundColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        setState(() {
                          _displayLimit = (_displayLimit + 15).clamp(0, filtered.length);
                        });
                      },
                      icon: const Icon(Icons.expand_more, size: 16),
                      label: Text('Show ${filtered.length - _displayLimit} more'),
                    ),
                  if (_displayLimit > 5) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        setState(() {
                          _displayLimit = 5;
                        });
                      },
                      icon: const Icon(Icons.expand_less, size: 16),
                      label: const Text('Show less'),
                    ),
                  ],
                ],
              ),
            ],
          ],
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
