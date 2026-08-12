// lib/shared/widgets/desktop_page_container.dart
//
// Wraps a desktop page's content with the shared responsive padding/
// max-width rules: full window width is used up to DesktopTokens.pageMaxWidth
// (so cards don't stretch into unreadable ribbons on a 2560px+ monitor),
// and horizontal padding shrinks slightly below ~1360px so a 1280x720
// window isn't over-padded. Scrolling is the caller's choice — this only
// constrains width/padding.

import 'package:flutter/material.dart';
import 'package:talbotiq/core/theme/desktop_tokens.dart';

class DesktopPageContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? verticalPadding;

  const DesktopPageContainer({
    super.key,
    required this.child,
    this.verticalPadding,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = DesktopTokens.pagePaddingFor(constraints.maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: DesktopTokens.pageMaxWidth),
            child: Padding(
              padding: (verticalPadding ?? const EdgeInsets.symmetric(vertical: 24))
                  .add(EdgeInsets.symmetric(horizontal: hPad)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
