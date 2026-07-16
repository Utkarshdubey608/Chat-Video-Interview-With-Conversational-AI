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
        // Keep the range coherent: never let "from" exceed "to".
        if (_dateTo != null && _dateTo!.isBefore(picked)) _dateTo = picked;
      } else {
        _dateTo = picked;
        if (_dateFrom != null && _dateFrom!.isAfter(picked)) _dateFrom = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.read<InterviewRepository>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Analytics')),
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
            // No interviews at all — nothing to filter, so no filter bar.
            return const AppMessageState(
              icon: Icons.insights_outlined,
              title: 'Nothing to analyze yet',
              subtitle:
                  'Create interviews and assign them to candidates — metrics '
                  'appear here as candidates take them.',
            );
          }

          // Test options come from the FULL list so the dropdown is stable
          // regardless of the other active filters.
          final testOptions = _service.testOptions(all);
          // Guard against a stale selection (e.g. the last interview of a test
          // group disappeared) so the dropdown value always matches an item.
          if (_testId != null &&
              !testOptions.any((o) => o.testId == _testId)) {
            _testId = null;
          }

          final filtered = _service.applyFilter(all, _filter);
          final summary = _service.compute(filtered);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterBar(
                track: _track,
                testId: _testId,
                dateFrom: _dateFrom,
                dateTo: _dateTo,
                roleController: _roleController,
                testOptions: testOptions,
                hasActiveFilter: _hasActiveFilter,
                onTrackChanged: (v) => setState(() => _track = v),
                onTestChanged: (v) => setState(() => _testId = v),
                onRoleChanged: () => setState(() {}),
                onPickFrom: () => _pickDate(isFrom: true),
                onPickTo: () => _pickDate(isFrom: false),
                onClearFrom: () => setState(() => _dateFrom = null),
                onClearTo: () => setState(() => _dateTo = null),
                onClear: _clearFilters,
              ),
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

// --------------------------------------------------------------------------
// Filter bar
// --------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final InterviewType? track;
  final String? testId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final TextEditingController roleController;
  final List<TestOption> testOptions;
  final bool hasActiveFilter;

  final ValueChanged<InterviewType?> onTrackChanged;
  final ValueChanged<String?> onTestChanged;
  final VoidCallback onRoleChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClearFrom;
  final VoidCallback onClearTo;
  final VoidCallback onClear;

  const _FilterBar({
    required this.track,
    required this.testId,
    required this.dateFrom,
    required this.dateTo,
    required this.roleController,
    required this.testOptions,
    required this.hasActiveFilter,
    required this.onTrackChanged,
    required this.onTestChanged,
    required this.onRoleChanged,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClearFrom,
    required this.onClearTo,
    required this.onClear,
  });

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Track filter -> Interview.type.
            _FilterField(
              child: DropdownButtonFormField<InterviewType?>(
                initialValue: track,
                isExpanded: true,
                decoration: _decoration(context, 'Track', Icons.tune_outlined),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All tracks')),
                  for (final t in InterviewType.values)
                    DropdownMenuItem(value: t, child: Text(_trackLabel(t))),
                ],
                onChanged: onTrackChanged,
              ),
            ),
            // Test/template filter -> Interview.testId.
            _FilterField(
              child: DropdownButtonFormField<String?>(
                initialValue: testId,
                isExpanded: true,
                decoration:
                    _decoration(context, 'Test', Icons.folder_copy_outlined),
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
                onChanged: testOptions.isEmpty ? null : onTestChanged,
              ),
            ),
            // Role / title search -> Interview.title.
            _FilterField(
              child: TextField(
                controller: roleController,
                onChanged: (_) => onRoleChanged(),
                textInputAction: TextInputAction.search,
                decoration: _decoration(
                  context,
                  'Role / title',
                  Icons.search,
                ).copyWith(
                  suffixIcon: roleController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear',
                          onPressed: () {
                            roleController.clear();
                            onRoleChanged();
                          },
                        ),
                ),
              ),
            ),
            // Date range -> Interview.createdAt.
            _DateField(
              label: 'From',
              value: dateFrom,
              onPick: onPickFrom,
              onClear: onClearFrom,
            ),
            _DateField(
              label: 'To',
              value: dateTo,
              onPick: onPickTo,
              onClear: onClearTo,
            ),
            // Clear action.
            TextButton.icon(
              onPressed: hasActiveFilter ? onClear : null,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }

  static InputDecoration _decoration(
      BuildContext context, String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

/// A fixed-min-width wrapper so filter controls line up and wrap gracefully on
/// narrow screens instead of overflowing.
class _FilterField extends StatelessWidget {
  final Widget child;
  const _FilterField({required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
      child: SizedBox(width: 200, child: child),
    );
  }
}

/// A date picker button showing the selected day (or a placeholder), with an
/// inline clear affordance. Uses showDatePicker; theme-aware via OutlinedButton.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasValue = value != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130, maxWidth: 200),
      child: OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.event_outlined, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                hasValue ? _fmtDay(value!) : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: onClear,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.clear, size: 16, color: scheme.onSurfaceVariant),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle('Funnel'),
              const SizedBox(height: 8),
              _FunnelCards(totals: summary.totals),
              const SizedBox(height: 24),
              _SectionTitle('Key metrics'),
              const SizedBox(height: 8),
              _KpiRow(summary: summary),
              const SizedBox(height: 24),
              _SectionTitle('Score distribution'),
              const SizedBox(height: 8),
              _Panel(child: _ScoreDistributionChart(summary: summary)),
              const SizedBox(height: 24),
              _SectionTitle('Recommendations'),
              const SizedBox(height: 8),
              _Panel(child: _RecommendationChart(summary: summary)),
              const SizedBox(height: 24),
              _SectionTitle('By interview type'),
              const SizedBox(height: 8),
              _ByTypeCards(byType: summary.byType),
              const SizedBox(height: 24),
              _SectionTitle('Average score by day'),
              const SizedBox(height: 8),
              _Panel(child: _TrendChart(trend: summary.trend)),
              const SizedBox(height: 24),
              _SectionTitle('Top candidates'),
              const SizedBox(height: 8),
              _TopCandidatesList(candidates: summary.topCandidates),
            ],
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------------------
// Funnel stat cards
// --------------------------------------------------------------------------

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
        icon: Icons.list_alt_outlined,
        color: scheme.primary,
      ),
      _StatCard(
        label: 'Assigned',
        value: '${totals.assigned}',
        icon: Icons.assignment_outlined,
        color: scheme.outline,
      ),
      _StatCard(
        label: 'In progress',
        value: '${totals.inProgress}',
        icon: Icons.hourglass_bottom_outlined,
        color: Colors.orange,
      ),
      _StatCard(
        label: 'Completed',
        value: '${totals.completed}',
        icon: Icons.check_circle_outline,
        color: Colors.green,
      ),
      _StatCard(
        label: 'Published',
        value: '${totals.published}',
        icon: Icons.publish_outlined,
        color: scheme.tertiary,
      ),
    ];
    return _ResponsiveGrid(children: cards);
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// Optional secondary line shown under the value (e.g. completion rate).
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 2),
            Text(
              footnote!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// KPI row
// --------------------------------------------------------------------------

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
          label: 'Completion rate',
          value: '${(summary.completionRate * 100).round()}%',
          icon: Icons.percent_outlined,
          color: scheme.primary,
        ),
        _StatCard(
          label: 'Avg. score',
          value: avg == null ? '—' : avg.toStringAsFixed(1),
          icon: Icons.grade_outlined,
          color: scheme.tertiary,
        ),
        _StatCard(
          label: 'Scored',
          value: '${summary.scoredCount}',
          icon: Icons.fact_check_outlined,
          color: Colors.green,
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------
// Score distribution bar chart
// --------------------------------------------------------------------------

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

    // Guard the axis so a max of 0 never reaches fl_chart.
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
                '${buckets[group.x].label}\n${rod.toY.round()}',
                TextStyle(
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                      style: theme.textTheme.bodySmall);
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
                        style: theme.textTheme.labelSmall),
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
              color: scheme.outlineVariant.withValues(alpha: 0.4),
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
                    width: 18,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
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

// --------------------------------------------------------------------------
// Recommendation pie chart
// --------------------------------------------------------------------------

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
    final total =
        dist.values.fold<int>(0, (sum, v) => sum + v);

    if (total == 0) {
      return const _EmptyChart(message: 'No recommendations recorded yet.');
    }

    final entries = AnalyticsService.recommendationDisplayKeys
        .where((k) => (dist[k] ?? 0) > 0)
        .toList();

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 44,
              sections: [
                for (final k in entries)
                  PieChartSectionData(
                    value: (dist[k] ?? 0).toDouble(),
                    color: colors[k],
                    radius: 56,
                    title: '${dist[k]}',
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final k in AnalyticsService.recommendationDisplayKeys)
              _LegendDot(
                color: colors[k]!,
                label:
                    '${_labels[k]} · ${dist[k] ?? 0}',
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
      opacity: muted ? 0.4 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: textColor)),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// By-type cards
// --------------------------------------------------------------------------

class _ByTypeCards extends StatelessWidget {
  final List<TypeStat> byType;
  const _ByTypeCards({required this.byType});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ResponsiveGrid(
      children: [
        for (final t in byType)
          _StatCard(
            label: t.label,
            value: t.averageScore == null
                ? '${t.count} · avg —'
                : '${t.count} · avg ${t.averageScore!.toStringAsFixed(1)}',
            footnote: '${(t.completionRate * 100).round()}% completed',
            icon: _iconFor(t.type),
            color: scheme.primary,
          ),
      ],
    );
  }

  static IconData _iconFor(InterviewType type) {
    switch (type) {
      case InterviewType.video:
        return Icons.videocam_outlined;
      case InterviewType.chat:
        return Icons.chat_bubble_outline;
      case InterviewType.voice:
        return Icons.mic_none_outlined;
    }
  }
}

// --------------------------------------------------------------------------
// Trend chart (interviews created per day)
// --------------------------------------------------------------------------

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
    // Average score lives on a fixed 0–100 domain, so the axis never depends on
    // the data (and never feeds fl_chart a zero range).
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
              color: scheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                      style: theme.textTheme.bodySmall);
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
                        style: theme.textTheme.labelSmall),
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
              isCurved: false,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(show: trend.length <= 12),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _bottomInterval(int n) {
    if (n <= 1) return 1;
    // Aim for ~5 labels max to avoid crowding.
    final step = (n / 5).ceil();
    return step.toDouble();
  }
}

// --------------------------------------------------------------------------
// Top candidates
// --------------------------------------------------------------------------

class _TopCandidatesList extends StatelessWidget {
  final List<TopCandidate> candidates;
  const _TopCandidatesList({required this.candidates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (candidates.isEmpty) {
      return _Panel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No scored candidates yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return _Panel(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var k = 0; k < candidates.length; k++)
            _CandidateRow(rank: k + 1, candidate: candidates[k]),
        ],
      ),
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

  /// Opens the same result surface the recruiter uses from the home list
  /// (EvaluateInterviewPage). Fetches the full interview on demand; no-ops if it
  /// can't be loaded.
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
    return ListTile(
      onTap: _open,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text('${widget.rank}',
            style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700)),
      ),
      title: Text(widget.candidate.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(widget.candidate.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${widget.candidate.score}',
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 18,
            height: 18,
            child: _loading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(Icons.chevron_right,
                    size: 18, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Shared layout primitives
// --------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// A wrap-based grid whose tile width adapts to the available space so nothing
/// overflows horizontally on narrow or wide screens.
class _ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  const _ResponsiveGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        // Target ~160px tiles, at least 2 per row, at most 5.
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
      height: 120,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

/// A "nice" grid/label interval that keeps at most ~5 lines and is never 0.
double _niceInterval(double maxY) {
  if (maxY <= 5) return 1;
  final raw = maxY / 5;
  return raw.ceilToDouble();
}

String _fmtDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtDayShort(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
