// lib/shared/widgets/talbotiq_wordmark.dart
//
// The app's actual in-UI branding is a text wordmark (no logo image is used
// anywhere in the app UI — assets/logo.jpg is only the OS app icon source),
// e.g. recruiter_home.dart's `_Wordmark` and login_page.dart's title. This
// promotes that same treatment to one shared widget instead of a third
// hand-rolled copy in the new desktop top nav.

import 'package:flutter/material.dart';

class TalbotiqWordmark extends StatelessWidget {
  final double fontSize;

  const TalbotiqWordmark({super.key, this.fontSize = 20});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.titleLarge?.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        children: [
          const TextSpan(text: 'talbot'),
          TextSpan(
            text: 'iq',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
