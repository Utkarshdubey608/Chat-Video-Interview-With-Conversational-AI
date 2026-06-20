import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../providers/app_store.dart';
import '../../../../widgets/custom_buttons.dart';

/// A tab in the interview sidebar that displays real-time speech and emotion metrics
/// (Confidence, Anxiety, Engagement, WPM, Fillers) and allows context override.
class LiveAiTab extends StatelessWidget {
  final AppStore store;
  final TextEditingController overrideController;
  final VoidCallback onSendOverride;

  const LiveAiTab({
    super.key,
    required this.store,
    required this.overrideController,
    required this.onSendOverride,
  });

  /// Builds a linear metric bar representing one of the candidate's real-time emotional stats.
  Widget _buildLiveMetricBar(BuildContext context, String label, int value, Color color) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            Text(
              '$value%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 6,
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.outline.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value / 100.0,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color chartColor = theme.brightness == Brightness.dark
        ? AppColors.humeTeal
        : theme.colorScheme.secondary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.2),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EMOTION ANALYSIS',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.wifi, color: chartColor, size: 10),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE FEED',
                          style: TextStyle(
                            color: chartColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildLiveMetricBar(
                  context,
                  'Confidence',
                  store.confidence,
                  theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                _buildLiveMetricBar(
                  context,
                  'Anxiety',
                  store.anxiety,
                  theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                _buildLiveMetricBar(
                  context,
                  'Engagement',
                  store.engagement,
                  theme.colorScheme.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.04),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.12),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WPM',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${store.wpm}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.04),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.12),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FILLERS',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${store.fillers}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (store.currentConversation?.properties?.applyConversationOverride == true) ...[
            Divider(color: theme.colorScheme.outline.withOpacity(0.12)),
            const SizedBox(height: 12),
            Text(
              'OVERRIDE (SAY THIS NOW)',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: overrideController,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type text for avatar to say…',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'Send',
                  height: 38,
                  onPressed: onSendOverride,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
