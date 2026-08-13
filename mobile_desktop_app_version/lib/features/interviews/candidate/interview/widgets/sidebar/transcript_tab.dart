import 'package:flutter/material.dart';

/// A tab in the interview sidebar shown during the call. The candidate's audio
/// is recorded locally and transcribed by Deepgram once the interview ends, so
/// there is no live feed here — the full transcript appears on the Results page.
class TranscriptTab extends StatelessWidget {
  const TranscriptTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fiber_manual_record,
                color: theme.colorScheme.error,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Recording your answers',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your audio is being captured for transcription. '
              'The full transcript and analysis will appear on the Results '
              'page once you end the interview.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
