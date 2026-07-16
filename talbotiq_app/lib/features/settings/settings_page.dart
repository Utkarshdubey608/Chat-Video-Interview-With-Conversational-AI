// lib/views/settings_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/shared/widgets/apple_ui.dart';
import 'package:talbotiq/features/app_config/app_config_service.dart';
import 'package:talbotiq/features/guide/mimic_guide_page.dart';
import 'package:talbotiq/features/settings/sections/api_credentials_section.dart';
import 'package:talbotiq/features/settings/sections/session_setup_section.dart';
import 'package:talbotiq/features/settings/sections/recording_storage_section.dart';
import 'package:talbotiq/features/settings/sections/webhook_section.dart';
import 'package:talbotiq/features/settings/sections/appearance_section.dart';

/// Settings shell. Keeps this file small: an Apple-style large title, a category
/// navigator (sidebar rail on wide screens, scrollable pills on narrow) and the
/// active category section. Each category lives in its own file under
/// `views/settings/` and owns its own controllers + Save action.
class SettingsPage extends StatefulWidget {
  /// When true (recruiter surface only) the page shows a "Sync API keys to
  /// cloud" action so candidate devices can pull the org's keys. Never enabled
  /// for candidates — they only ever consume keys.
  final bool showCloudSync;

  const SettingsPage({super.key, this.showCloudSync = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _category = 0;
  bool _syncing = false;

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
                    if (widget.showCloudSync) ...[
                      _buildCloudSyncCard(theme),
                      const SizedBox(height: 24),
                    ],
                    if (isWide) _buildWide(theme) else _buildNarrow(theme),
                    const SizedBox(height: 24),
                    _buildGuideEntry(theme),
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

  // Pushes this recruiter's saved API keys to the cloud so their candidates'
  // devices can pull them at launch (see AppConfigService). Recruiter-only —
  // gated by [SettingsPage.showCloudSync].
  Future<void> _syncKeys() async {
    if (_syncing) return;
    final messenger = ScaffoldMessenger.of(context);
    final appConfig = context.read<AppConfigService>();
    final store = context.read<AppStore>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    setState(() => _syncing = true);
    try {
      await appConfig.pushForRecruiter(uid, store);
      messenger.showSnackBar(
        const SnackBar(content: Text('API keys synced to cloud.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // Recruiter-only card: sync saved API keys to the cloud for candidate pull.
  Widget _buildCloudSyncCard(ThemeData theme) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.6)),
      ),
      child: ListTile(
        leading: const AppleIconBadge(
          icon: Icons.cloud_upload_outlined,
          color: Color(0xFF0EA5E9),
          size: 32,
        ),
        title: Text(
          'Sync API keys to cloud',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          'Push your saved keys so candidates you assign can reach Tavus / Gemini during their interviews.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: _syncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                onPressed: _syncKeys,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Sync'),
              ),
      ),
    );
  }

  // Single entry point into the Mimic Guide help assistant.
  Widget _buildGuideEntry(ThemeData theme) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.6)),
      ),
      child: ListTile(
        leading: const AppleIconBadge(
          icon: Icons.support_agent,
          color: Color(0xFF10B981),
          size: 32,
        ),
        title: Text(
          'Help & Guide',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          'Ask the Mimic Guide how to use templates, sessions, scoring and reports.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Icon(Icons.chevron_right,
            size: 20, color: theme.colorScheme.onSurfaceVariant),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MimicGuidePage()),
        ),
      ),
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
