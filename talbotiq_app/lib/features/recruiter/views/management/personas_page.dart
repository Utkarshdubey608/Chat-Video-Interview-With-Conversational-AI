// lib/features/recruiter/views/management/personas_page.dart
//
// Recruiter-side: view the Tavus personas available on the configured account.
// READ-ONLY management surface built on the EXISTING, unmodified
// `tavusService.listPersonas()`. It does not modify the Tavus service or any
// interview code. Editing/creating personas is intentionally deferred to a
// separate additive service so the interview-critical TavusService stays locked.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:talbotiq/core/services/tavus_service.dart';
import 'package:talbotiq/shared/models/app_models.dart';
import 'package:talbotiq/shared/providers/app_store.dart';
import 'package:talbotiq/features/recruiter/views/widgets/recruiter_ui.dart';

class PersonasPage extends StatefulWidget {
  const PersonasPage({super.key});

  @override
  State<PersonasPage> createState() => _PersonasPageState();
}

class _PersonasPageState extends State<PersonasPage> {
  bool _loading = true;
  String? _error;
  List<TavusPersona> _personas = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final hasKey = context.read<AppStore>().tavusKey.trim().isNotEmpty;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!hasKey) {
      setState(() {
        _loading = false;
        _error =
            'No Tavus API key configured. Add one in Settings to view personas.';
      });
      return;
    }
    try {
      final list = await tavusService.listPersonas();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _personas = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _showDetail(TavusPersona p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PersonaDetailSheet(persona: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personas'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return RecruiterEmptyState(
        icon: Icons.key_off_outlined,
        title: 'Unavailable',
        description: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_personas.isEmpty) {
      return const RecruiterEmptyState(
        icon: Icons.face_retouching_natural_outlined,
        title: 'No personas',
        description:
            'This Tavus account has no personas yet. Create them in the Tavus '
            'dashboard, then refresh.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          const RecruiterPageHeader(
            kicker: 'Avatar',
            title: 'Personas',
            subtitle: 'Interviewer personalities available on your Tavus '
                'account.',
          ),
          const SizedBox(height: 20),
          for (final p in _personas) ...[
            RecruiterPanel(
              onTap: () => _showDetail(p),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.personaName.isEmpty
                              ? '(unnamed persona)'
                              : p.personaName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.personaId,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PersonaDetailSheet extends StatelessWidget {
  final TavusPersona persona;
  const _PersonaDetailSheet({required this.persona});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = persona;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.personaName.isEmpty ? '(unnamed persona)' : p.personaName,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _kv(context, 'Persona ID', p.personaId, copyable: true),
            if (p.defaultReplicaId != null && p.defaultReplicaId!.isNotEmpty)
              _kv(context, 'Default replica', p.defaultReplicaId!,
                  copyable: true),
            if (p.systemPrompt.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('System prompt', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(p.systemPrompt, style: theme.textTheme.bodyMedium),
            ],
            if (p.context != null && p.context!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Context', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(p.context!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v,
      {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(k,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: SelectableText(v)),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: v));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied.')));
              },
            ),
        ],
      ),
    );
  }
}
