import 'package:flutter/material.dart';

/// Panel showcasing tags for candidate strengths and watch points side-by-side.
class StrengthsWatchpointsPanel extends StatelessWidget {
  final List<String> strengths;
  final List<String> watchPoints;

  const StrengthsWatchpointsPanel({
    super.key,
    required this.strengths,
    required this.watchPoints,
  });

@override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Helper to generate preview text when collapsed
    String getPreviewText(List<String> items) {
      if (items.isEmpty) return 'None';
      if (items.length <= 2) return items.join(', ');
      return '${items.take(2).join(', ')} +${items.length - 2} more';
    }

    return Column(
      children: [
        // -----------------------------------------------------------------
        // 1. Strengths Card
        // -----------------------------------------------------------------
        Card(
          elevation: 0,
          // Pitch Black Background
          color: Colors.black, 
          // More rounded borders (radius: 16)
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            // Optional: subtle grey outline to separate black card from potential black app background
            side: const BorderSide(color: Color.fromARGB(255, 68, 214, 66), width: 0.6), 
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            // Overriding theme colors just for this black card to ensure contrast
            data: theme.copyWith(
              dividerColor: Colors.transparent,
              iconTheme: const IconThemeData(color: Colors.white), // Makes expansion arrow white
              colorScheme: theme.colorScheme.copyWith(
                onSurface: Colors.white, // Setting default text inside to white
              ),
            ),
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              leading: Container(
                padding: const EdgeInsets.all(10), // Bigger padding
                decoration: BoxDecoration(
                  // Primary color with good visibility on black
                  color: theme.colorScheme.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(30), // Matching rounder aesthetic
                ),
                // Better icon: Material Icon Check Circle
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 20, // Slightly bigger
                ),
              ),
              title: Text(
                'Strengths',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                getPreviewText(strengths),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: strengths
                        .map(
                          (s) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              // Darker tag bg for contrast inside black card
                              color: theme.colorScheme.primary.withOpacity(0.12),
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.3),
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                // Brighter primary text to stand out
                                color: Color.lerp(theme.colorScheme.primary, Colors.white, 0.2),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // -----------------------------------------------------------------
        // 2. Watch Points Card
        // -----------------------------------------------------------------
        Card(
          elevation: 0,
          // Pitch Black Background
          color: Colors.black,
          // More rounded borders (radius: 16)
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            // Optional subtle outline
            side: const BorderSide(color: Color.fromARGB(255, 236, 73, 73), width: 0.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: theme.copyWith(
              dividerColor: Colors.transparent,
              iconTheme: const IconThemeData(color: Colors.white), // Makes expansion arrow white
              colorScheme: theme.colorScheme.copyWith(
                onSurface: Colors.white, // Default text white
              ),
            ),
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              leading: Container(
                padding: const EdgeInsets.all(10), // Bigger padding
                decoration: BoxDecoration(
                  // Error color visible on black
                  color: theme.colorScheme.error.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(30), // Rounder
                ),
                // Better icon: Material Icon Error Outline
                child: Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                  size: 20, // Slightly bigger
                ),
              ),
              title: Text(
                'Watch Points',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                getPreviewText(watchPoints),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: watchPoints
                        .map(
                          (w) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              // Darker tag bg
                              color: theme.colorScheme.error.withOpacity(0.12),
                              border: Border.all(
                                color: theme.colorScheme.error.withOpacity(0.3),
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              w,
                              style: TextStyle(
                                // Brighter error text
                                color: Color.lerp(theme.colorScheme.error, Colors.white, 0.2),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
