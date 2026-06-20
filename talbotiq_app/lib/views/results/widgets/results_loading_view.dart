import 'package:flutter/material.dart';
import '../../../models/app_models.dart';

/// A loading view displaying a three-step progressive analysis pipeline:
/// 1. Tavus Transcript Retrieval
/// 2. Hume Vocal/Prosody Emotion Analysis
/// 3. Gemini ATS Scorecard Synthesis
class ResultsLoadingView extends StatelessWidget {
  final bool fetchingTranscript;
  final bool humeProcessing;
  final bool geminiLoading;
  final List<TranscriptEntry> sessionTranscript;
  final ATSScorecard? atsScorecard;
  final String? geminiError;

  const ResultsLoadingView({
    super.key,
    required this.fetchingTranscript,
    required this.humeProcessing,
    required this.geminiLoading,
    required this.sessionTranscript,
    required this.atsScorecard,
    required this.geminiError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Processing Interview Results',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please wait while we compile and analyze the session data.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.12),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Step 1: Tavus Transcript Retrieval
                    ProgressStepWidget(
                      stepTitle: 'Step 1: Finalising Tavus transcript',
                      isActive: fetchingTranscript,
                      isDone: !fetchingTranscript,
                      statusText: fetchingTranscript
                          ? 'Retrieving from server…'
                          : (sessionTranscript.isEmpty ? 'Failed' : 'Completed'),
                      isFailed: !fetchingTranscript && sessionTranscript.isEmpty,
                    ),
                    const Divider(height: 24),

                    // Step 2: Hume Emotional Analysis
                    ProgressStepWidget(
                      stepTitle: 'Step 2: Processing prosody & facial emotions',
                      isActive: !fetchingTranscript && humeProcessing,
                      isDone: !fetchingTranscript && !humeProcessing,
                      statusText: fetchingTranscript
                          ? 'Pending Step 1'
                          : (humeProcessing ? 'Analyzing recording…' : 'Completed'),
                      isFailed: false,
                    ),
                    const Divider(height: 24),

                    // Step 3: Gemini Scorecard Synthesis
                    ProgressStepWidget(
                      stepTitle: 'Step 3: Synthesizing ATS scorecard',
                      isActive: !fetchingTranscript && !humeProcessing && geminiLoading,
                      isDone: !fetchingTranscript &&
                          !humeProcessing &&
                          !geminiLoading &&
                          atsScorecard != null,
                      statusText: (fetchingTranscript || humeProcessing)
                          ? 'Pending Step 2'
                          : (geminiLoading
                              ? 'Generating scorecard with Gemini…'
                              : (atsScorecard == null && geminiError != null
                                  ? 'Failed'
                                  : 'Completed')),
                      isFailed: !fetchingTranscript &&
                          !humeProcessing &&
                          !geminiLoading &&
                          atsScorecard == null &&
                          geminiError != null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single step widget inside the ResultsLoadingView to indicate progress,
/// showing active progress indicators or status check/cancel icons.
class ProgressStepWidget extends StatelessWidget {
  final String stepTitle;
  final bool isActive;
  final bool isDone;
  final String statusText;
  final bool isFailed;

  const ProgressStepWidget({
    super.key,
    required this.stepTitle,
    required this.isActive,
    required this.isDone,
    required this.statusText,
    required this.isFailed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData iconData = Icons.radio_button_unchecked;
    Color iconColor = theme.colorScheme.outline;

    if (isActive) {
      return Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stepTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (isFailed) {
      iconData = Icons.cancel_outlined;
      iconColor = theme.colorScheme.error;
    } else if (isDone) {
      iconData = Icons.check_circle_outline;
      iconColor = Colors.green;
    }

    return Row(
      children: [
        Icon(iconData, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stepTitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDone
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
              Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isFailed
                      ? theme.colorScheme.error
                      : (isDone
                          ? Colors.green
                          : theme.colorScheme.onSurface.withValues(alpha: 0.38)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
