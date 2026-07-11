// lib/widgets/custom_buttons.dart
import 'package:flutter/material.dart';
import '../core/constants/colors.dart';

enum ButtonVariant { primary, secondary, outline, ghost, danger }

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final ButtonVariant variant;
  final double? width;
  final double height;
  final Widget? icon;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.variant = ButtonVariant.primary,
    this.width,
    this.height = 48, // Standardised M3 touch target height
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textCol;
    BorderSide border = BorderSide.none;

    switch (variant) {
      case ButtonVariant.primary:
        bg = AppColors.primary;
        textCol = AppColors.backgroundBlack; // High contrast dark text on light primary
        break;
      case ButtonVariant.secondary:
        bg = AppColors.backgroundDarker;
        textCol = AppColors.textLight;
        border = const BorderSide(color: AppColors.border, width: 1);
        break;
      case ButtonVariant.outline:
        bg = Colors.transparent;
        textCol = AppColors.textLight;
        border = const BorderSide(color: AppColors.border, width: 1);
        break;
      case ButtonVariant.ghost:
        bg = Colors.transparent;
        textCol = AppColors.textMuted;
        break;
      case ButtonVariant.danger:
        bg = AppColors.dangerBg;
        textCol = AppColors.danger;
        border = const BorderSide(color: AppColors.dangerBorder, width: 1);
        break;
    }

    final childWidget = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(textCol),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          icon!,
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: TextStyle(
            color: textCol,
            fontSize: 14,
            fontWeight: FontWeight.w500, // M3 label font weight
            fontFamily: 'Inter',
          ),
        ),
      ],
    );

    return SizedBox(
      width: width,
      height: height,
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          side: border,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100), // M3 stadium pill shape
          ),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: height >= 48 ? 12 : 6),
        ),
        child: childWidget,
      ),
    );
  }
}
