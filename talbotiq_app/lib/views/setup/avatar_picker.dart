// lib/views/setup/avatar_picker.dart
import 'package:flutter/material.dart';
import '../../models/app_models.dart';

/// A horizontal, FaceTime-style strip of selectable avatar (replica) tiles.
/// Each tile shows a circular monogram, the replica name and status, with a
/// primary ring + checkmark on the current selection.
class AvatarStrip extends StatelessWidget {
  final List<TavusReplica> replicas;
  final String selectedId;
  final ValueChanged<String> onSelect;

  const AvatarStrip({
    super.key,
    required this.replicas,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (replicas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.face_retouching_off,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No replicas loaded yet. Add your Tavus key in Settings, then refresh.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: replicas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final r = replicas[i];
          return _AvatarTile(
            replica: r,
            selected: r.replicaId == selectedId,
            onTap: () => onSelect(r.replicaId),
          );
        },
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final TavusReplica replica;
  final bool selected;
  final VoidCallback onTap;

  const _AvatarTile({
    required this.replica,
    required this.selected,
    required this.onTap,
  });

  // First two initials of the replica name for the monogram.
  String get _initials {
    final parts = replica.replicaName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReady = replica.status.toLowerCase() == 'ready' ||
        replica.status.toLowerCase() == 'completed';

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary.withOpacity(0.85),
                        theme.colorScheme.secondary.withOpacity(0.85),
                      ],
                    ),
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surface,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary,
                        border: Border.all(
                            color: theme.colorScheme.surface, width: 2),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.check, size: 13, color: Colors.white),
                    ),
                  ),
                if (replica.replicaType == 'stock')
                  Positioned(
                    left: -2,
                    top: -2,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.6)),
                      ),
                      child: Text(
                        'STOCK',
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              replica.replicaName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isReady
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  replica.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
