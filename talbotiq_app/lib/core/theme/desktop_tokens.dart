// lib/core/theme/desktop_tokens.dart
//
// Shared spacing/sizing constants for the recruiter desktop redesign. These
// are additive — they don't replace AppTheme/AppColors (the existing
// Talbotiq color identity, typography and global CardTheme are untouched),
// they just give the new desktop-only widgets (DesktopTopNav, MetricCard,
// the redesigned Analytics dashboard, etc.) one consistent, named scale
// instead of re-picking pixel values in every file.

class DesktopTokens {
  DesktopTokens._();

  // Spacing scale.
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;

  // Card/panel radius for the new premium-SaaS surfaces. Deliberately
  // tighter than the app's existing global CardTheme radius (24-28px,
  // tuned for the mobile/candidate UI) — this is scoped to the new desktop
  // widgets only, not a change to the shared theme.
  static const double cardRadius = 14;

  // Top nav.
  static const double topNavHeight = 68;

  // Content column: caps line length on very wide/ultrawide desktop
  // windows (2560px+) so cards don't stretch into unreadable ribbons,
  // while still using the full window width on narrower desktop sizes.
  static const double pageMaxWidth = 1600;
  static const double pagePadding = 32;
  static const double pagePaddingCompact = 20;

  /// Page horizontal padding scaled down on the narrower end of the desktop
  /// range (1280px-class windows) per the "reduce spacing at smaller widths"
  /// requirement, without collapsing all the way to a phone-style padding.
  static double pagePaddingFor(double width) =>
      width < 1360 ? pagePaddingCompact : pagePadding;
}
