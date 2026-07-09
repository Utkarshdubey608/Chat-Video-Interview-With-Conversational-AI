// lib/views/settings_page.dart
import 'package:flutter/material.dart';
import 'settings/api_credentials_section.dart';
import 'settings/session_setup_section.dart';
import 'settings/recording_storage_section.dart';
import 'settings/webhook_section.dart';

/// Settings shell. Keeps this file small: a header, a category selector and the
/// active category section. Each category lives in its own file under
/// `views/settings/` and owns its own controllers + Save action.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _category = 0;

  // Category metadata; index maps 1:1 to the sections kept alive below.
  static const List<_CategoryMeta> _categories = [
    _CategoryMeta('API Credentials', Icons.vpn_key_outlined),
    _CategoryMeta('Session Setup', Icons.tune),
    _CategoryMeta('Recording & Storage', Icons.videocam_outlined),
    _CategoryMeta('Webhook', Icons.webhook_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 24),
                  _buildCategorySelector(theme),
                  const SizedBox(height: 24),
                  // Keep every section alive so unsaved edits survive switching.
                  IndexedStack(
                    index: _category,
                    children: const [
                      ApiCredentialsSection(),
                      SessionSetupSection(),
                      RecordingStorageSection(),
                      WebhookSection(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Page title block.
  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Platform Config',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.secondary,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Settings',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage API credentials and platform behaviour by category.',
          style: theme.textTheme.bodyMedium,
          softWrap: true,
        ),
      ],
    );
  }

  // Dropdown that switches the visible settings category.
  Widget _buildCategorySelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surfaceVariant,
            border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _category,
              isExpanded: true,
              dropdownColor: theme.colorScheme.surfaceVariant,
              icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant),
              onChanged: (val) => setState(() => _category = val ?? 0),
              items: [
                for (int i = 0; i < _categories.length; i++)
                  DropdownMenuItem<int>(
                    value: i,
                    child: Row(
                      children: [
                        Icon(_categories[i].icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Text(
                          _categories[i].label,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
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

// Label + icon pair for one settings category.
class _CategoryMeta {
  final String label;
  final IconData icon;
  const _CategoryMeta(this.label, this.icon);
}
