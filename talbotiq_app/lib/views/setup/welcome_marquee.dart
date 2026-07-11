import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';

/// One welcome / feature card in the setup marquee.
class WelcomeCardSpec {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;

  const WelcomeCardSpec({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
  });
}

/// A premium, continuously auto-scrolling band of welcome / feature cards shown
/// full-bleed across the top of the Interview Setup page.
///
/// The strip loops seamlessly by rendering two identical card sets and
/// translating the whole row by exactly one set's width. Every card is a fixed
/// width, so the loop distance is computed directly — deterministic from the
/// first frame, no post-frame measurement.
class SetupWelcomeMarquee extends StatefulWidget {
  const SetupWelcomeMarquee({super.key});

  @override
  State<SetupWelcomeMarquee> createState() => _SetupWelcomeMarqueeState();
}

class _SetupWelcomeMarqueeState extends State<SetupWelcomeMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _cardWidth = 268;
  static const double _gap = 14;
  static const double _stripHeight = 104;

  static const List<WelcomeCardSpec> _cards = [
    WelcomeCardSpec(
      icon: Icons.waving_hand_rounded,
      gradient: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
      title: 'Welcome to TalbotIQ',
      subtitle: 'Let’s set up your interview',
    ),
    WelcomeCardSpec(
      icon: Icons.smart_toy_outlined,
      gradient: [AppColors.accent, Color(0xFF818CF8)],
      title: 'AI Avatar Interviews',
      subtitle: 'Lifelike, real-time video',
    ),
    WelcomeCardSpec(
      icon: Icons.insights_rounded,
      gradient: [AppColors.primary, AppColors.primaryHover],
      title: 'Emotion Analysis',
      subtitle: 'Confidence & engagement, live',
    ),
    WelcomeCardSpec(
      icon: Icons.assessment_outlined,
      gradient: [AppColors.humeTeal, Color(0xFF5EEAD4)],
      title: 'Instant Scorecards',
      subtitle: 'ATS-ready results in seconds',
    ),
    WelcomeCardSpec(
      icon: Icons.tune_rounded,
      gradient: [Color(0xFF6366F1), Color(0xFFA855F7)],
      title: 'Fully Customisable',
      subtitle: 'Tailor questions & persona',
    ),
    WelcomeCardSpec(
      icon: Icons.lock_outline_rounded,
      gradient: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
      title: 'Private & Secure',
      subtitle: 'Recordings stay on device',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 38),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final double setWidth = _cards.length * (_cardWidth + _gap);

    Widget oneSet() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in _cards) ...[
              _WelcomeCard(spec: s, width: _cardWidth),
              const SizedBox(width: _gap),
            ],
          ],
        );

    final strip = ClipRect(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(-_controller.value * setWidth, 0),
              child: child,
            );
          },
          // OverflowBox lets the two-set row lay out at its full natural width
          // (far wider than the viewport) without a RenderFlex overflow; the
          // parent ClipRect clips whatever falls outside the band.
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [oneSet(), oneSet()],
            ),
          ),
        ),
      ),
    );

    // Soft edge fade so cards elegantly appear/dissolve at the band's edges.
    final masked = ShaderMask(
      shaderCallback: (rect) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.05, 0.95, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: strip,
    );

    return Container(
      height: _stripHeight,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.accent.withOpacity(0.12),
                  theme.colorScheme.surface.withOpacity(0.0),
                  AppColors.primary.withOpacity(0.10),
                ]
              : [
                  AppColors.accent.withOpacity(0.07),
                  theme.colorScheme.surface.withOpacity(0.0),
                  AppColors.primary.withOpacity(0.06),
                ],
        ),
      ),
      child: masked,
    );
  }
}

/// A single glassy welcome card: gradient badge, title + subtitle, and a large
/// translucent watermark icon in the background for a layered, premium feel.
class _WelcomeCard extends StatelessWidget {
  final WelcomeCardSpec spec;
  final double width;

  const _WelcomeCard({required this.spec, required this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = spec.gradient.first;

    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(isDark ? 0.35 : 0.22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(isDark ? 0.20 : 0.11),
            theme.colorScheme.surface,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.34 : 0.07),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -14,
            bottom: -18,
            child: Icon(
              spec.icon,
              size: 92,
              color: accent.withOpacity(isDark ? 0.13 : 0.09),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: spec.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(spec.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        spec.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          height: 1.25,
                          color: theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
