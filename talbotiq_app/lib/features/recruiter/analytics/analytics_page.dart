// lib/features/recruiter/analytics/analytics_page.dart
//
// Recruiter analytics dashboard. Reads the recruiter's own interviews live from
// Firestore (InterviewRepository.watchForRecruiter), runs the pure
// AnalyticsService over them, and renders funnel stat cards, a score-
// distribution bar chart, a recommendation pie chart, KPIs, a creation trend,
// and a top-candidates list. Fully theme-aware and responsive; every chart
// guards against empty series so fl_chart never divides by zero.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/shared/widgets/app_message_state.dart';
import 'package:talbotiq/shared/widgets/logout_button.dart';
import 'package:talbotiq/features/interviews/models/interview.dart';
import 'package:talbotiq/features/interviews/recruiter/evaluate_interview_page.dart';
import 'package:talbotiq/features/interviews/services/interview_repository.dart';
import 'package:talbotiq/features/recruiter/analytics/analytics_service.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  static const _service = AnalyticsService();

  // Filter state. The interview list is filtered by these BEFORE
  // AnalyticsService.compute, so every metric/chart reflects the filtered set.
  InterviewType? _track; // null = All tracks
  String? _testId; // null = All tests
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final TextEditingController _roleController = TextEditingController();

  @override
  void dispose() {
    _roleController.dispose();
    super.dispose();
  }

  AnalyticsFilter get _filter => AnalyticsFilter(
        track: _track,
        testId: _testId,
        roleQuery: _roleController.text,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );

  bool get _hasActiveFilter => _filter.isActive;

  int get _activeFilterCount {
    int count = 0;
    if (_track != null) count++;
    if (_testId != null) count++;
    if (_roleController.text.isNotEmpty) count++;
    if (_dateFrom != null) count++;
    if (_dateTo != null) count++;
    return count;
  }

  void _clearFilters() {
    setState(() {
      _track = null;
      _testId = null;
      _dateFrom = null;
      _dateTo = null;
      _roleController.clear();
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _dateFrom : _dateTo) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
        if (_dateTo != null && _dateTo!.isBefore(picked)) _dateTo = picked;
      } else {
        _dateTo = picked;
        if (_dateFrom != null && _dateFrom!.isAfter(picked)) _dateFrom = picked;
      }
    });
  }

  static String _trackLabel(InterviewType t) {
    switch (t) {
      case InterviewType.video:
        return 'Video';
      case InterviewType.chat:
        return 'Chat';
      case InterviewType.voice:
        return 'Voice';
    }
  }

  static InputDecoration _inputDecoration(
      BuildContext context, String label, IconData icon) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  void _openFilterSheet(BuildContext context, List<TestOption> testOptions) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.of(sheetContext).viewInsets.bottom + 32,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filter Analytics',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_activeFilterCount > 0)
                          TextButton(
                            onPressed: () {
                              _clearFilters();
                              setSheetState(() {});
                              Navigator.pop(sheetContext);
                            },
                            child: const Text('Clear All'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Track Dropdown
                    DropdownButtonFormField<InterviewType?>(
                      value: _track,
                      isExpanded: true,
                      decoration: _inputDecoration(context, 'Track', Icons.tune_outlined),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All tracks')),
                        for (final t in InterviewType.values)
                          DropdownMenuItem(value: t, child: Text(_trackLabel(t))),
                      ],
                      onChanged: (val) {
                        setState(() => _track = val);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    // Test Dropdown
                    DropdownButtonFormField<String?>(
                      value: _testId,
                      isExpanded: true,
                      decoration: _inputDecoration(context, 'Test', Icons.folder_copy_outlined),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All tests')),
                        for (final o in testOptions)
                          DropdownMenuItem(
                            value: o.testId,
                            child: Text(
                              '${o.label} (${o.count})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: testOptions.isEmpty
                          ? null
                          : (val) {
                              setState(() => _testId = val);
                              setSheetState(() {});
                            },
                    ),
                    const SizedBox(height: 16),
                    // Role Title search
                    TextField(
                      controller: _roleController,
                      onChanged: (val) {
                        setState(() {});
                        setSheetState(() {});
                      },
                      decoration: _inputDecoration(context, 'Role / title', Icons.search).copyWith(
                        suffixIcon: _roleController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _roleController.clear();
                                  setState(() {});
                                  setSheetState(() {});
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Date pickers in a Row
                    Row(
                      children: [
                        Expanded(
                          child: _DateFieldSheet(
                            label: 'From Date',
                            value: _dateFrom,
                            onPick: () async {
                              await _pickDate(isFrom: true);
                              setSheetState(() {});
                            },
                            onClear: () {
                              setState(() => _dateFrom = null);
                              setSheetState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateFieldSheet(
                            label: 'To Date',
                            value: _dateTo,
                            onPick: () async {
                              await _pickDate(isFrom: false);
                              setSheetState(() {});
                            },
                            onClear: () {
                              setState(() => _dateTo = null);
                              setSheetState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      ),
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Apply Filters'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveFilterChips(List<TestOption> testOptions) {
    final chips = <Widget>[];

    if (_track != null) {
      chips.add(_FilterChip(
        label: 'Track: ${_trackLabel(_track!)}',
        onDeleted: () => setState(() => _track = null),
      ));
    }
    if (_testId != null) {
      final option = testOptions.firstWhere(
        (o) => o.testId == _testId,
        orElse: () => const TestOption(testId: '', label: '', count: 0),
      );
      if (option.testId.isNotEmpty) {
        chips.add(_FilterChip(
          label: 'Test: ${option.label}',
          onDeleted: () => setState(() => _testId = null),
        ));
      }
    }
    if (_roleController.text.isNotEmpty) {
      chips.add(_FilterChip(
        label: 'Role: ${_roleController.text}',
        onDeleted: () {
          _roleController.clear();
          setState(() {});
        },
      ));
    }
    if (_dateFrom != null) {
      chips.add(_FilterChip(
        label: 'From: ${_fmtDayShort(_dateFrom!)}',
        onDeleted: () => setState(() => _dateFrom = null),
      ));
    }
    if (_dateTo != null) {
      chips.add(_FilterChip(
        label: 'To: ${_fmtDayShort(_dateTo!)}',
        onDeleted: () => setState(() => _dateTo = null),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          ...chips,
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _clearFilters,
            child: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
        title: const Text('Analytics'),
        actions: const [LogoutButton(), SizedBox(width: 4)],
      ),
      body: StreamBuilder<List<Interview>>(
        stream: repo.watchForRecruiter(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return AppMessageState(
              icon: Icons.error_outline,
              title: 'Could not load analytics',
              subtitle: '${snap.error}',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          if (all.isEmpty) {
            return const AppMessageState(
              icon: Icons.insights_outlined,
              title: 'Nothing to analyze yet',
              subtitle:
                  'Create interviews and assign them to candidates — metrics '
                  'appear here as candidates take them.',
            );
          }

          final testOptions = _service.testOptions(all);
          if (_testId != null &&
              !testOptions.any((o) => o.testId == _testId)) {
            _testId = null;
          }

          final filtered = _service.applyFilter(all, _filter);
          final summary = _service.compute(filtered);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clean Header with filter trigger button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Dashboard Overview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openFilterSheet(context, testOptions),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.filter_list_rounded, size: 16),
                      label: Text(
                        _activeFilterCount > 0 ? 'Filters (${_activeFilterCount})' : 'Filter',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              _buildActiveFilterChips(testOptions),
              Expanded(
                child: summary.isEmpty
                    ? AppMessageState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'No interviews match these filters',
                        subtitle: _hasActiveFilter
                            ? 'Adjust or clear the filters to see your metrics.'
                            : 'Nothing to analyze yet.',
                      )
                    : _Dashboard(summary: summary),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;

  const _FilterChip({required this.label, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
        ),
        backgroundColor: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onDeleted: onDeleted,
        deleteIcon: const Icon(Icons.close, size: 14),
      ),
    );
  }
}

class _DateFieldSheet extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateFieldSheet({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.event_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasValue ? _fmtDay(value!) : 'Select Date',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: hasValue ? FontWeight.bold : FontWeight.normal,
                      color: hasValue ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.clear, size: 16, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final AnalyticsSummary summary;
  const _Dashboard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle('Funnel Status'),
          const SizedBox(height: 12),
          _FunnelCards(totals: summary.totals),
          const SizedBox(height: 28),
          _SectionTitle('Key Performance Indicators'),
          const SizedBox(height: 12),
          _KpiRow(summary: summary),
          const SizedBox(height: 28),
          _SectionTitle('Score Distribution'),
          const SizedBox(height: 12),
          _Panel(child: _ScoreDistributionChart(summary: summary)),
          const SizedBox(height: 28),
          _SectionTitle('AI Candidate Recommendations'),
          const SizedBox(height: 12),
          _Panel(child: _RecommendationChart(summary: summary)),
          const SizedBox(height: 28),
          _SectionTitle('Analytics By Track Type'),
          const SizedBox(height: 12),
          _ByTypeCards(byType: summary.byType),
          const SizedBox(height: 28),
          _SectionTitle('Average Performance Trend (Scores Over Time)'),
          const SizedBox(height: 12),
          _Panel(child: _TrendChart(trend: summary.trend)),
          const SizedBox(height: 28),
          _SectionTitle('Top Scoring Candidates'),
          const SizedBox(height: 12),
          _TopCandidatesList(candidates: summary.topCandidates),
        ],
      ),
    );
  }
}

class _FunnelCards extends StatelessWidget {
  final FunnelTotals totals;
  const _FunnelCards({required this.totals});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cards = <Widget>[
      _StatCard(
        label: 'Total',
        value: '${totals.total}',
        icon: Icons.analytics_outlined,
        color: scheme.primary,
      ),
      _StatCard(
        label: 'Assigned',
        value: '${totals.assigned}',
        icon: Icons.assignment_ind_outlined,
        color: scheme.outline,
      ),
      _StatCard(
        label: 'In Progress',
        value: '${totals.inProgress}',
        icon: Icons.pending_outlined,
        color: Colors.orange,
      ),
      _StatCard(
        label: 'Completed',
        value: '${totals.completed}',
        icon: Icons.task_alt_rounded,
        color: Colors.green,
      ),
      _StatCard(
        label: 'Published',
        value: '${totals.published}',
        icon: Icons.verified_user_outlined,
        color: scheme.secondary,
      ),
    ];
    return SizedBox(
      height: 125, // Height to fit card content without clipping
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 145, // Consistent width for slider look
            child: cards[index],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? footnote;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(
              footnote!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final AnalyticsSummary summary;
  const _KpiRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avg = summary.averageOverallScore;
    return _ResponsiveGrid(
      children: [
        _StatCard(
          label: 'Completion Rate',
          value: '${(summary.completionRate * 100).round()}%',
          icon: Icons.pie_chart_outline_rounded,
          color: scheme.primary,
        ),
        _StatCard(
          label: 'Avg. Score',
          value: avg == null ? '—' : avg.toStringAsFixed(1),
          icon: Icons.stars_rounded,
          color: scheme.secondary,
        ),
        _StatCard(
          label: 'Evaluated Candidates',
          value: '${summary.scoredCount}',
          icon: Icons.checklist_rtl_rounded,
          color: Colors.green,
        ),
      ],
    );
  }
}

class _ScoreDistributionChart extends StatelessWidget {
  final AnalyticsSummary summary;
  const _ScoreDistributionChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buckets = summary.scoreDistribution;
    final maxCount =
        buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);

    if (summary.scoredCount == 0) {
      return const _EmptyChart(message: 'No scored interviews yet.');
    }

    final maxY = (maxCount == 0 ? 1 : maxCount).toDouble();

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${buckets[group.x].label}\n${rod.toY.round()} Candidates',
                TextStyle(
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _niceInterval(maxY),
                getTitlesWidget: (value, meta) {
                  if (value != value.roundToDouble()) {
                    return const SizedBox.shrink();
                  }
                  return Text('${value.round()}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(buckets[idx].label,
                        style: theme.textTheme.labelSmall?.copyWith(fontSize: 9, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(maxY),
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var k = 0; k < buckets.length; k++)
              BarChartGroupData(
                x: k,
                barRods: [
                  BarChartRodData(
                    toY: buckets[k].count.toDouble(),
                    color: scheme.primary,
                    width: 20,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6), // Rounded tops!
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationChart extends StatelessWidget {
  final AnalyticsSummary summary;
  const _RecommendationChart({required this.summary});

  static const _labels = {
    'strong_yes': 'Strong yes',
    'yes': 'Yes',
    'maybe': 'Maybe',
    'no': 'No',
    'unknown': 'Unknown',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dist = summary.recommendationDistribution;
    final colors = <String, Color>{
      'strong_yes': Colors.green,
      'yes': Colors.lightGreen,
      'maybe': Colors.orange,
      'no': Colors.redAccent,
      'unknown': scheme.outline,
    };
    final total = dist.values.fold<int>(0, (sum, v) => sum + v);

    if (total == 0) {
      return const _EmptyChart(message: 'No recommendations recorded yet.');
    }

    final entries = AnalyticsService.recommendationDisplayKeys
        .where((k) => (dist[k] ?? 0) > 0)
        .toList();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 55, // Clean, spacious donut hole
              sections: [
                for (final k in entries)
                  PieChartSectionData(
                    value: (dist[k] ?? 0).toDouble(),
                    color: colors[k],
                    radius: 24, // Thinner, modern slices
                    showTitle: false, // Don't overflow slice text, read Legend instead
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final k in AnalyticsService.recommendationDisplayKeys)
              _LegendDot(
                color: colors[k]!,
                label: '${_labels[k]} · ${dist[k] ?? 0}',
                muted: (dist[k] ?? 0) == 0,
                textColor: scheme.onSurface,
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool muted;
  final Color textColor;
  const _LegendDot({
    required this.color,
    required this.label,
    required this.muted,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: muted ? 0.35 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle, // Circular legend dots!
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
          ),
        ],
      ),
    );
  }
}

class _ByTypeCards extends StatelessWidget {
  final List<TypeStat> byType;
  const _ByTypeCards({required this.byType});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 145, // Height to fit card + footnote safely
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: byType.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final t = byType[index];
          return SizedBox(
            width: 165,
            child: _StatCard(
              label: t.label,
              value: t.averageScore == null
                  ? '${t.count} · avg —'
                  : '${t.count} · avg ${t.averageScore!.toStringAsFixed(1)}',
              footnote: '${(t.completionRate * 100).round()}% completed',
              icon: _iconFor(t.type),
              color: scheme.primary,
            ),
          );
        },
      ),
    );
  }

  static IconData _iconFor(InterviewType type) {
    switch (type) {
      case InterviewType.video:
        return Icons.videocam_rounded;
      case InterviewType.chat:
        return Icons.chat_bubble_rounded;
      case InterviewType.voice:
        return Icons.mic_rounded;
    }
  }
}

class _TrendChart extends StatelessWidget {
  final List<TrendPoint> trend;
  const _TrendChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (trend.isEmpty) {
      return const _EmptyChart(message: 'No scored interviews yet.');
    }
    const maxY = 100.0;
    const gridInterval = 20.0;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          minX: 0,
          maxX: (trend.length - 1).toDouble().clamp(0, double.infinity),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => spots.map((s) {
                final p = trend[s.x.round().clamp(0, trend.length - 1)];
                return LineTooltipItem(
                  '${_fmtDay(p.day)}\n'
                  'avg ${p.averageScore.toStringAsFixed(1)} · ${p.count} scored',
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: gridInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: gridInterval,
                getTitlesWidget: (value, meta) {
                  if (value != value.roundToDouble()) {
                    return const SizedBox.shrink();
                  }
                  return Text('${value.round()}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _bottomInterval(trend.length),
                getTitlesWidget: (value, meta) {
                  final idx = value.round();
                  if (idx < 0 || idx >= trend.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_fmtDayShort(trend[idx].day),
                        style: theme.textTheme.labelSmall?.copyWith(fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var k = 0; k < trend.length; k++)
                  FlSpot(k.toDouble(), trend[k].averageScore),
              ],
              isCurved: true, // Smooth curved line!
              color: scheme.primary,
              barWidth: 4,
              dotData: FlDotData(show: trend.length <= 12),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.25),
                    scheme.primary.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ), // Premium gradient fill!
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _bottomInterval(int n) {
    if (n <= 1) return 1;
    final step = (n / 5).ceil();
    return step.toDouble();
  }
}

class _TopCandidatesList extends StatelessWidget {
  final List<TopCandidate> candidates;
  const _TopCandidatesList({required this.candidates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (candidates.isEmpty) {
      return _Panel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              'No scored candidates yet.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var k = 0; k < candidates.length; k++)
          _CandidateRow(rank: k + 1, candidate: candidates[k]),
      ],
    );
  }
}

class _CandidateRow extends StatefulWidget {
  final int rank;
  final TopCandidate candidate;
  const _CandidateRow({required this.rank, required this.candidate});

  @override
  State<_CandidateRow> createState() => _CandidateRowState();
}

class _CandidateRowState extends State<_CandidateRow> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    final navigator = Navigator.of(context);
    final repo = context.read<InterviewRepository>();
    Interview? interview;
    try {
      interview = await repo.getById(widget.candidate.interviewId);
    } catch (_) {
      interview = null;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (interview == null) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => EvaluateInterviewPage(interview: interview!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Color rankBg;
    Color rankText;
    if (widget.rank == 1) {
      rankBg = Colors.amber.shade700;
      rankText = Colors.white;
    } else if (widget.rank == 2) {
      rankBg = Colors.grey.shade400;
      rankText = Colors.white;
    } else if (widget.rank == 3) {
      rankBg = Colors.brown.shade400;
      rankText = Colors.white;
    } else {
      rankBg = scheme.primaryContainer.withValues(alpha: 0.3);
      rankText = scheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100), // Fully pill-shaped rows!
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3), width: 1.0),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: rankBg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${widget.rank}',
                      style: TextStyle(
                        color: rankText,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.candidate.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${widget.candidate.score}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 12),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(28), // 28.0 Roundness
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3), width: 1.0),
      ),
      child: child,
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  const _ResponsiveGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        var perRow = (maxW / 170).floor();
        if (perRow < 2) perRow = 2;
        if (perRow > 5) perRow = 5;
        const spacing = 12.0;
        final tileW = (maxW - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final c in children)
              SizedBox(width: tileW, child: c),
          ],
        );
      },
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String message;
  const _EmptyChart({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

double _niceInterval(double maxY) {
  if (maxY <= 5) return 1;
  final raw = maxY / 5;
  return raw.ceilToDouble();
}

String _fmtDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtDayShort(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
