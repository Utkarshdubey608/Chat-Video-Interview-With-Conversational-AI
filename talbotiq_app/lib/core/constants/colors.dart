// lib/core/constants/colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Material Design 3 Restrained Dark Palette
  static const Color background = Color(0xFF111318);       // Soft dark grey (M3 surface)
  static const Color backgroundDarker = Color(0xFF1A1C1E); // Tonal surface
  static const Color backgroundBlack = Color(0xFF0E1013);  // Deepest neutral surface
  
  // Clean border and cards
  static const Color cardBg = Color(0xFF1E2025);           // M3 Surface Container
  static const Color border = Color(0xFF43474E);           // M3 Outline Variant
  static const Color borderLight = Color(0x26FFFFFF);      // Minimal opacity border
  
  // Brand accents (Restrained M3 Emerald Green & Slate Blue)
  static const Color primary = Color(0xFF81D7A3);         // M3 Dark Primary (Clean Emerald)
  static const Color primaryHover = Color(0xFF98EBB9);
  static const Color primaryLight = Color(0xFF003920);     // Dark primary container
  static const Color accent = Color(0xFFA2CDDB);           // M3 Dark Tertiary (Slate Blue)
  static const Color accentLight = Color(0x1FA2CDDB);      // Tertiary translucent
  
  // Feedback colors (M3 aligned)
  static const Color success = Color(0xFF81D7A3);          // Standardised success
  static const Color successBg = Color(0xFF003920);
  static const Color successBorder = Color(0xFF005232);
  
  static const Color warning = Color(0xFFE4C270);
  static const Color warningBg = Color(0xFF3C2E00);
  static const Color warningBorder = Color(0xFF574300);
  
  static const Color danger = Color(0xFFF2B8B5);           // M3 Dark Error
  static const Color dangerBg = Color(0xFF601410);
  static const Color dangerBorder = Color(0xFF8C1D18);
  
  // Grays / Neutral text
  static const Color textLight = Color(0xFFE2E2E6);        // M3 On Surface
  static const Color textMuted = Color(0xFF8D9199);        // M3 On Surface Variant
  static const Color textDark = Color(0xFF111318);         // M3 Light On Surface
  
  // Hume specific branding (Restrained M3 Teal)
  static const Color humeBase = Color(0xFF1A1C1E);
  static const Color humeCard = Color(0xFF242629);
  static const Color humeBorder = Color(0xFF3F4145);
  static const Color humeText = Color(0xFFE2E2E6);
  static const Color humeMuted = Color(0xFF8D9199);
  static const Color humeTeal = Color(0xFF80CBC4);        // Subtle pastel teal
}
