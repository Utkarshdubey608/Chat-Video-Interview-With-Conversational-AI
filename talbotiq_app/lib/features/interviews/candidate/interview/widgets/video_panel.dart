import 'package:flutter/material.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/shared/widgets/custom_buttons.dart';
import 'package:talbotiq/shared/widgets/iframe_view.dart';
import 'package:talbotiq/features/interviews/candidate/interview/widgets/pulsing_avatar.dart';

/// A widget that displays the main video panel for the interview.
/// If a real Tavus conversation URL is available and active, it loads the iframe.
/// Otherwise, it shows the demo placeholder with a pulsing avatar.
class VideoPanel extends StatelessWidget {
  final AppStore store;
  final List<String> validQs;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const VideoPanel({
    super.key,
    required this.store,
    required this.validQs,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  /// Builds a linear progress bar indicating the progress through the questions.
  Widget _buildProgressBar(ThemeData theme, List<String> validQs, int currentQ) {
    final double pct = validQs.isEmpty ? 0 : (currentQ + 1) / validQs.length;
    return Container(
      height: 4,
      width: double.infinity,
      color: theme.colorScheme.outline.withOpacity(0.12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: pct,
          child: Container(color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  /// Builds a placeholder visual when there is no active video stream (Demo Mode).
  Widget _buildDemoPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PulsingAvatar(),
          const SizedBox(height: 16),
          Text(
            'Demo Mode',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Avatar speech and transcripts are simulated.\nPress Next (⏭) to advance questions.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 850;
    final hasUrl = store.currentConversation?.conversationUrl.isNotEmpty ?? false;

    return Container(
      color: theme.colorScheme.surface,
      child: Stack(
        children: [
          Center(
            child: Container(
              margin: EdgeInsets.all(isMobile ? 12 : 24),
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.12),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (hasUrl && store.currentRoute == '/interview')
                    ? buildIframe(store.currentConversation!.conversationUrl)
                    : _buildDemoPlaceholder(theme),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildProgressBar(theme, validQs, store.currentQuestionIdx),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: CustomButton(
              text: isFullscreen ? 'Exit Full Screen' : 'Full Screen',
              variant: ButtonVariant.outline,
              height: 36,
              icon: Icon(
                isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 16,
                color: theme.colorScheme.onSurface,
              ),
              onPressed: onToggleFullscreen,
            ),
          ),
        ],
      ),
    );
  }
}
