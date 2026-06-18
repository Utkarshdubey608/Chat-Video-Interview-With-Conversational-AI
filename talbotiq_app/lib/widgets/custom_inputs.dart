// lib/widgets/custom_inputs.dart
import 'package:flutter/material.dart';
import '../core/constants/colors.dart';

class CustomInputField extends StatelessWidget {
  final String label;
  final String? hint;
  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool isPassword;
  final TextInputType keyboardType;
  final Widget? suffix;
  final int maxLines;
  final bool autofocus;

  const CustomInputField({
    super.key,
    required this.label,
    this.hint,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.suffix,
    this.maxLines = 1,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8), // M3 consistent 8dp spacing
        TextField(
          controller: controller,
          onChanged: onChanged,
          obscureText: isPassword,
          keyboardType: keyboardType,
          maxLines: maxLines,
          autofocus: autofocus,
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurface,
            fontFamily: 'Inter',
          ),
          decoration: InputDecoration(
            hintText: placeholder,
            suffixIcon: suffix,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
        ],
      ],
    );
  }
}

class CustomSelectDropdown<T> extends StatelessWidget {
  final String label;
  final String? hint;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hintText;

  const CustomSelectDropdown({
    super.key,
    required this.label,
    this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8), // M3 consistent 8dp spacing
        InputButtonDecorator(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              dropdownColor: theme.colorScheme.surfaceVariant,
              icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant),
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
                fontFamily: 'Inter',
              ),
              isExpanded: true,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
        ],
      ],
    );
  }
}

// Wraps dropdown in identical style as text fields to align height and borders
class InputButtonDecorator extends StatelessWidget {
  final Widget child;

  const InputButtonDecorator({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 56, // Matches standard M3 text field height with vertical padding
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12), // Matches input borders
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class CustomSlider extends StatelessWidget {
  final String label;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;
  final String Function(double)? formatValue;

  const CustomSlider({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
    this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              formatValue != null ? formatValue!(value) : value.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8), // M3 consistent 8dp spacing
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.outline.withOpacity(0.2),
            thumbColor: theme.colorScheme.primary,
            overlayColor: theme.colorScheme.primary.withOpacity(0.12),
            valueIndicatorColor: theme.colorScheme.surfaceVariant,
            trackHeight: 4,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class CustomToggle extends StatelessWidget {
  final String label;
  final String description;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const CustomToggle({
    super.key,
    required this.label,
    required this.description,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0), // Better target size
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: checked,
            onChanged: onChanged,
            activeColor: theme.colorScheme.primary,
            activeTrackColor: theme.colorScheme.primary.withOpacity(0.24),
            inactiveThumbColor: theme.colorScheme.onSurfaceVariant,
            inactiveTrackColor: theme.colorScheme.outline.withOpacity(0.12),
          ),
        ],
      ),
    );
  }
}
