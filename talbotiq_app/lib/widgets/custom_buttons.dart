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
    this.height = 42,
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
        textCol = Colors.white;
        break;
      case ButtonVariant.secondary:
        bg = const Color(0x1AFFFFFF);
        textCol = Colors.white;
        border = const BorderSide(color: AppColors.border, width: 1);
        break;
      case ButtonVariant.outline:
        bg = Colors.transparent;
        textCol = Colors.white;
        border = const BorderSide(color: Color(0x33FFFFFF), width: 1);
        break;
      case ButtonVariant.ghost:
        bg = Colors.transparent;
        textCol = AppColors.textMuted;
        break;
      case ButtonVariant.danger:
        bg = const Color(0x1ADB2626);
        textCol = AppColors.danger;
        border = const BorderSide(color: Color(0x40DB2626), width: 1);
        break;
    }

    final childWidget = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );

    return SizedBox(
      width: width,
      height: height,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          side: border,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: childWidget,
      ),
    );
  }
}
