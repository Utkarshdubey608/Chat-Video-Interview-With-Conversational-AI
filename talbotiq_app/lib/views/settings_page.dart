// lib/views/settings_page.dart
import 'package:flutter/material.dart';
import '../widgets/apple_ui.dart';
import 'settings/api_credentials_section.dart';
import 'settings/session_setup_section.dart';
import 'settings/recording_storage_section.dart';
import 'settings/webhook_section.dart';
import 'settings/appearance_section.dart';

/// Settings shell. Keeps this file small: an Apple-style large title, a category
/// navigator (sidebar rail on wide screens, scrollable pills on narrow) and the
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
    _CategoryMeta('API Credentials', Icons.vpn_key_outlined, Color(0xFF0EA5E9)),
    _CategoryMeta('Session Setup', Icons.tune, Color(0xFF6366F1)),
    _CategoryMeta('Recording & Storage', Icons.videocam_outlined, Color(0xFFEF4444)),
    _CategoryMeta('Webhook', Icons.webhook_outlined, Color(0xFFA855F7)),
    _CategoryMeta('Appearance', Icons.palette_outlined, Color(0xFFF59E0B)),
  ];

  // The live section widgets, kept alive so unsaved edits survive switching.
  static const List<Widget> _sections = [
    ApiCredentialsSection(),
    SessionSetupSection(),
    RecordingStorageSection(),
    WebhookSection(),
    AppearanceSection(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 840;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppleLargeTitle(
                      eyebrow: 'Platform Config',
                      title: 'Settings',
                      subtitle: isWide
                          ? 'Manage credentials and platform behaviour by category.'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    if (isWide) _buildWide(theme) else _buildNarrow(theme),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Wide layout: fixed sidebar rail + the active section.
  Widget _buildWide(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 232, child: _buildRail(theme)),
        const SizedBox(width: 28),
        Expanded(
          child: IndexedStack(index: _category, children: _sections),
        ),
      ],
    );
  }

  // Narrow layout: horizontal category pills stacked above the active section.
  Widget _buildNarrow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _buildPill(theme, i),
          ),
        ),
        const SizedBox(height: 24),
        IndexedStack(index: _category, children: _sections),
      ],
    );
  }

  // Sidebar rail: a grouped list of selectable category rows (macOS style).
  Widget _buildRail(ThemeData theme) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.6)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _categories.length; i++)
            _buildRailRow(theme, i),
        ],
      ),
    );
  }

  Widget _buildRailRow(ThemeData theme, int i) {
    final meta = _categories[i];
    final selected = i == _category;
    return InkWell(
      onTap: () => setState(() => _category = i),
      child: Container(
        color: selected ? theme.colorScheme.primary.withOpacity(0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            AppleIconBadge(icon: meta.icon, color: meta.color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                meta.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.primary.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }

  // A single category pill for the narrow layout.
  Widget _buildPill(ThemeData theme, int i) {
    final meta = _categories[i];
    final selected = i == _category;
    return GestureDetector(
      onTap: () => setState(() => _category = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(meta.icon,
                size: 16,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              meta.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Label + icon + accent colour for one settings category.
class _CategoryMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _CategoryMeta(this.label, this.icon, this.color);
}
