import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../providers/app_store.dart';

/// A tab in the interview sidebar that displays a live transcription feed of the
/// conversation (candidate vs. interviewer) and connection status.
class TranscriptTab extends StatelessWidget {
  final AppStore store;
  final bool dgConnected;
  final String? transcriptError;
  final String interimText;
  final ScrollController transcriptScrollController;

  const TranscriptTab({
    super.key,
    required this.store,
    required this.dgConnected,
    required this.transcriptError,
    required this.interimText,
    required this.transcriptScrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color chartColor = theme.brightness == Brightness.dark
        ? AppColors.humeTeal
        : theme.colorScheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              kIsWeb ? 'DEEPGRAM NOVA-3' : 'DEVICE SPEECH',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dgConnected
                        ? chartColor
                        : theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  dgConnected
                      ? 'LIVE'
                      : (transcriptError != null
                          ? 'UNAVAILABLE'
                          : (kIsWeb && store.deepgramKey.isEmpty
                              ? 'NO KEY'
                              : 'CONNECTING…')),
                  style: TextStyle(
                    color: dgConnected
                        ? chartColor
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (store.sessionTranscript.isEmpty && interimText.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0),
            child: Text(
              !kIsWeb
                  ? (transcriptError != null
                      ? 'Device speech unavailable. Results will try the Tavus transcript after the call ends.'
                      : (dgConnected
                          ? 'Listening — transcript will appear as you speak…'
                          : 'Starting device speech recognition…'))
                  : (store.deepgramKey.isEmpty
                      ? 'Transcript requires a Deepgram API key in Settings.'
                      : (dgConnected
                          ? 'Listening — transcript will appear as you speak…'
                          : 'Connecting to Deepgram…')),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: transcriptScrollController,
            itemCount: store.sessionTranscript.length + (interimText.isNotEmpty ? 1 : 0),
            itemBuilder: (context, idx) {
              // Trailing interim "typing" entry
              if (idx >= store.sessionTranscript.length) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.02),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.12),
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Typing…',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        interimText,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 13,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final entry = store.sessionTranscript[idx];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Q${entry.questionIdx + 1} · ${entry.role == 'avatar' ? 'Interviewer' : 'Candidate'}',
                          style: TextStyle(
                            color: entry.role == 'avatar'
                                ? theme.colorScheme.secondary
                                : theme.colorScheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateTime.fromMillisecondsSinceEpoch(entry.timestamp)
                              .toLocal()
                              .toString()
                              .split(' ')
                              .last
                              .substring(0, 8),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                            fontSize: 9,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.text,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
