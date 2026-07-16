import 'package:flutter/material.dart';
import '../../../../providers/app_store.dart';
import '../../../../widgets/custom_buttons.dart';

/// A tab in the interview sidebar.
///
/// Communication and sentiment analysis (speaking pace, filler words,
/// confidence, engagement, emotional tone) are NOT computed live during the
/// call — they are produced by the post-interview pipeline (Deepgram
/// transcription + Hume/ATS analysis) on the results page. This tab therefore
/// shows an honest "analyzed after your interview" panel rather than any
/// live-looking numbers. It also hosts the optional operator context-override
/// control when the session enables it.
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

  /// One line item describing a metric that will be produced after the call.
  Widget _analyzedItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Analyzed after your interview',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Your communication and sentiment are not scored live. Once '
                  'the interview ends, your responses are transcribed and '
                  'analyzed, and the results appear on your report.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _analyzedItem(
                  context,
                  Icons.record_voice_over_outlined,
                  'Speaking pace and filler words',
                ),
                _analyzedItem(
                  context,
                  Icons.emoji_emotions_outlined,
                  'Confidence, engagement and emotional tone',
                ),
                _analyzedItem(
                  context,
                  Icons.assignment_turned_in_outlined,
                  'Answer quality and overall scorecard',
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'No live metrics are shown during the call.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (store.currentConversation?.properties?.applyConversationOverride == true) ...[
            const SizedBox(height: 16),
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
