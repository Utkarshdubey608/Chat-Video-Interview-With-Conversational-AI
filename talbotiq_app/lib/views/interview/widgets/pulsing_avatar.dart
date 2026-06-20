import 'package:flutter/material.dart';

/// A widget that displays a pulsing person avatar, used as a placeholder
/// during demo mode when no real live video stream is available.
class PulsingAvatar extends StatefulWidget {
  const PulsingAvatar({super.key});

  @override
  State<PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withOpacity(0.12),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(
                0.3 + _controller.value * 0.5,
              ),
              width: 2 + _controller.value * 2,
            ),
          ),
          child: Icon(Icons.person, color: theme.colorScheme.primary, size: 36),
        );
      },
    );
  }
}
