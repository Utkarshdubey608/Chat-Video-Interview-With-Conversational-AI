// lib/core/constants/colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Material Design 3 Restrained Dark Palette - Premium Neutrals
  static const Color background = Color(0xFF0A0B0E);       // Calming rich dark navy/black
  static const Color backgroundDarker = Color(0xFF12141C); // Tonal surface 
  static const Color backgroundBlack = Color(0xFF060709);  // Deepest black for contrast
  
  // Clean border and cards
  static const Color cardBg = Color(0xFF161822);           // Premium slate card background
  static const Color border = Color(0xFF222632);           // Very subtle dark border
  static const Color borderLight = Color(0x14FFFFFF);      // Translucent light border
  
  // Brand accents (Refined Emerald Green & Premium Indigo)
  static const Color primary = Color(0xFF10B981);         // Radiant modern Emerald
  static const Color primaryHover = Color(0xFF34D399);     // Lighter emerald for hover
  static const Color primaryLight = Color(0xFF064E3B);     // Deep pine container
  static const Color accent = Color(0xFF6366F1);           // Vibrant Indigo Accent (Apple/Linear feel)
  static const Color accentLight = Color(0x206366F1);      // Subtle translucent Indigo
  
  // Feedback colors (M3 aligned)
  static const Color success = Color(0xFF10B981);          // Aligned success green
  static const Color successBg = Color(0xFF064E3B);
  static const Color successBorder = Color(0xFF047857);
  
  static const Color warning = Color(0xFFF59E0B);          // Amber warnings
  static const Color warningBg = Color(0xFF78350F);
  static const Color warningBorder = Color(0xFFB45309);
  
  static const Color danger = Color(0xFFEF4444);           // M3 Clean Error Red
  static const Color dangerBg = Color(0xFF7F1D1D);
  static const Color dangerBorder = Color(0xFF991B1B);
  
  // Grays / Neutral text
  static const Color textLight = Color(0xFFF3F4F6);        // Clean near-white
  static const Color textMuted = Color(0xFF9CA3AF);        // Muted gray
  static const Color textDark = Color(0xFF111827);         // Rich light-mode text
  
  // Hume specific branding (Restrained M3 Teal)
  static const Color humeBase = Color(0xFF12141C);
  static const Color humeCard = Color(0xFF1A1D29);
  static const Color humeBorder = Color(0xFF2E3347);
  static const Color humeText = Color(0xFFF3F4F6);
  static const Color humeMuted = Color(0xFF9CA3AF);
  static const Color humeTeal = Color(0xFF2DD4BF);        // Radiant premium teal
}
