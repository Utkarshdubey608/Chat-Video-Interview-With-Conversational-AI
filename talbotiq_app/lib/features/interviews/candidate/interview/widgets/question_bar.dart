import 'package:flutter/material.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';

/// A widget that displays the current question, status (e.g. speaking),
/// and controls (next, prev, end, auto/manual advance mode) at the bottom.
class QuestionBar extends StatelessWidget {
  final AppStore store;
  final List<String> validQs;
  final bool avatarSpeaking;
  final bool autoAdvance;
  final int revealedIdx;
  final VoidCallback onToggleAutoAdvance;
  final VoidCallback onShowNow;
  final VoidCallback onPrevQuestion;
  final VoidCallback onNextQuestion;
  final VoidCallback onEndInterview;

  const QuestionBar({
    super.key,
    required this.store,
    required this.validQs,
    required this.avatarSpeaking,
    required this.autoAdvance,
    required this.revealedIdx,
    required this.onToggleAutoAdvance,
    required this.onShowNow,
    required this.onPrevQuestion,
    required this.onNextQuestion,
    required this.onEndInterview,
  });

  /// Builds a rounded action/navigation button for controls (prev, next, stop).
  Widget _buildRoundControlBtn(
    BuildContext context,
    IconData icon,
    VoidCallback? onPressed, {
    bool isDanger = false,
  }) {
    final theme = Theme.of(context);
    final disabled = onPressed == null;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDanger
            ? theme.colorScheme.error.withOpacity(0.08)
            : (disabled
                ? theme.colorScheme.onSurface.withOpacity(0.02)
                : theme.colorScheme.onSurface.withOpacity(0.06)),
        border: Border.all(
          color: isDanger
              ? theme.colorScheme.error.withOpacity(0.24)
              : (disabled
                  ? theme.colorScheme.outline.withOpacity(0.05)
                  : theme.colorScheme.outline.withOpacity(0.24)),
        ),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: 18,
          color: isDanger
              ? theme.colorScheme.error
              : (disabled
                  ? theme.colorScheme.onSurfaceVariant.withOpacity(0.4)
                  : theme.colorScheme.onSurface),
        ),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRevealed = revealedIdx == store.currentQuestionIdx;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 650;

        final questionTextCol = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'QUESTION ${store.currentQuestionIdx + 1} OF ${validQs.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                if (avatarSpeaking) ...[
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Avatar Speaking',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            isRevealed
                ? Text(
                    validQs.isNotEmpty
                        ? validQs[store.currentQuestionIdx]
                        : 'Done',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Row(
                    children: [
                      Text(
                        'Waiting for avatar to ask…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(width: 12),
                      CustomButton(
                        text: 'Show Now',
                        variant: ButtonVariant.outline,
                        height: 28,
                        onPressed: onShowNow,
                      ),
                    ],
                  ),
          ],
        );

        final controlsRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomButton(
              text: autoAdvance ? 'Auto' : 'Manual',
              variant: ButtonVariant.outline,
              height: 36,
              icon: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: autoAdvance
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              onPressed: onToggleAutoAdvance,
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 20,
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
            const SizedBox(width: 8),
            _buildRoundControlBtn(
              context,
              Icons.skip_previous,
              store.currentQuestionIdx > 0 ? onPrevQuestion : null,
            ),
            const SizedBox(width: 8),
            _buildRoundControlBtn(
              context,
              Icons.stop,
              onEndInterview,
              isDanger: true,
            ),
            const SizedBox(width: 8),
            _buildRoundControlBtn(
              context,
              Icons.skip_next,
              onNextQuestion,
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.12),
              ),
            ),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    questionTextCol,
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: Icon(
                            Icons.assignment_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          label: Text(
                            'Menu',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                        ),
                        controlsRow,
                      ],
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: questionTextCol),
                    const SizedBox(width: 16),
                    controlsRow,
                  ],
                ),
        );
      },
    );
  }
}
