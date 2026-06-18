// lib/core/constants/colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Dark Background theme
  static const Color background = Color.fromARGB(255, 0, 1, 3);
  static const Color backgroundDarker = Color(0xFF0A1628);
  static const Color backgroundBlack = Color(0xFF091525);
  
  // Translucent border and cards
  static const Color cardBg = Color.fromARGB(255, 0, 5, 13);
  static const Color border = Color(0xFF1E293B);
  static const Color borderLight = Color(0x33FFFFFF);
  
  // Brand accents
  static const Color primary = Color(0xFF0D5C3A); // Emerald green
  static const Color primaryHover = Color(0xFF1A8050);
  static const Color primaryLight = Color(0xFFF0FAF5);
  static const Color accent = Color(0xFFF0C040); // Amber yellow
  static const Color accentLight = Color(0x26F0C040); // Yellow translucent
  
  // Feedback colors
  static const Color success = Color(0xFF3DB36B);
  static const Color successBg = Color(0xFFF0FAF5);
  static const Color successBorder = Color(0xFFB3E9CD);
  
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);
  
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBg = Color(0xFFFEE2E2);
  static const Color dangerBorder = Color(0xFFFCA5A5);
  
  // Grays / Neutral text
  static const Color textLight = Color(0xFFF8FAFC);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textDark = Color(0xFF0F172A);
  
  // Hume specific branding
  static const Color humeBase = Color(0xFF0A1628);
  static const Color humeCard = Color(0xFF13223A);
  static const Color humeBorder = Color(0xFF1E3A5F);
  static const Color humeText = Color(0xFFE2E8F0);
  static const Color humeMuted = Color(0xFF64748B);
  static const Color humeTeal = Color(0xFF00FF9D);
}
