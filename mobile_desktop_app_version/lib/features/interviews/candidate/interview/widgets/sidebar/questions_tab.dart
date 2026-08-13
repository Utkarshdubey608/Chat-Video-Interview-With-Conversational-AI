import 'package:flutter/material.dart';
import 'package:talbotiq/shared/providers/app_store.dart';

/// A tab in the interview sidebar that lists the questions and their status
/// (completed, active, locked/hidden).
///
/// In [candidateMode] (the candidate-facing video flow) only the CURRENT
/// question is shown — upcoming/future questions are never rendered — and
/// tapping is disabled so the candidate cannot jump ahead. This is an
/// anti-cheat measure; the recruiter/operator view (candidateMode == false)
/// keeps the full, navigable list.
class QuestionsTab extends StatelessWidget {
  final AppStore store;
  final List<String> validQs;
  final int revealedIdx;
  final Function(int) onQuestionTap;
  final bool candidateMode;

  const QuestionsTab({
    super.key,
    required this.store,
    required this.validQs,
    required this.revealedIdx,
    required this.onQuestionTap,
    this.candidateMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // In candidate mode only the current question is visible; otherwise the
    // full set is listed. `visibleIndices` maps list rows -> question indices.
    final currentIdx = store.currentQuestionIdx;
    final List<int> visibleIndices = candidateMode
        ? (currentIdx >= 0 && currentIdx < validQs.length ? [currentIdx] : const [])
        : List<int>.generate(validQs.length, (i) => i);

    return ListView.builder(
      itemCount: visibleIndices.length,
      itemBuilder: (context, row) {
        final idx = visibleIndices[row];
        final isCurrent = store.currentQuestionIdx == idx;
        final isDone = idx < store.currentQuestionIdx;
        final isLocked = idx > store.currentQuestionIdx;
        final isRevealed = revealedIdx >= idx;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isCurrent
                ? theme.colorScheme.primary.withOpacity(0.08)
                : Colors.transparent,
            border: Border.all(
              color: isCurrent
                  ? theme.colorScheme.primary.withOpacity(0.24)
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            dense: true,
            // Candidates cannot jump to arbitrary questions.
            onTap: candidateMode ? null : () => onQuestionTap(idx),
            leading: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isDone
                    ? theme.colorScheme.primary
                    : (isCurrent
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.outline.withOpacity(0.12)),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                isDone ? '✓' : '${idx + 1}',
                style: TextStyle(
                  color: isDone || !isCurrent
                      ? Colors.white
                      : theme.colorScheme.onSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              !isRevealed && isCurrent
                  ? '••••••••••••••••••••••••'
                  : validQs[idx],
              style: TextStyle(
                color: isLocked
                    ? theme.colorScheme.onSurface.withOpacity(0.38)
                    : theme.colorScheme.onSurface,
                fontSize: 13,
                fontStyle: !isRevealed && isCurrent
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
