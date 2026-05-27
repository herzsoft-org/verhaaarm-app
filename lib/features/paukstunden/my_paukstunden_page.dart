import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/api_error_text.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

class MyPaukstundenPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const MyPaukstundenPage({
    super.key,
    required this.api,
    required this.authStore,
  });

  @override
  State<MyPaukstundenPage> createState() => _MyPaukstundenPageState();
}

class _MyPaukstundenPageState extends State<MyPaukstundenPage> {
  bool _loading = true;
  PaukstundenListDto? _data;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var currentUserId = widget.authStore.currentUser?.id;
      if (currentUserId == null) {
        try {
          currentUserId = (await widget.api.getMe()).id;
        } catch (_) {
          currentUserId = null;
        }
      }

      final data = await widget.api.getCurrentPaukstunden();

      if (!mounted) return;
      setState(() {
        _currentUserId = currentUserId;
        _data = data;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFriendlyApiError(
              e,
              fallback: 'Paukstunden konnten nicht geladen werden.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final changed = await context.push<bool>('/paukstunden/new');
    if (changed == true && mounted) {
      await _load();
    }
  }

  bool _canEdit(PaukstundenEntryDto entry) {
    final currentUserId = _currentUserId;

    if (currentUserId == null) {
      return true;
    }

    return entry.participants.any((p) => p.id == currentUserId);
  }

  Future<void> _openEdit(PaukstundenEntryDto entry) async {
    final changed = await context.push<bool>(
      '/paukstunden/${entry.id}/edit',
      extra: entry,
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  Future<void> _delete(PaukstundenEntryDto entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paukstunde löschen?'),
        content: const Text('Diese Paukstunden-Session wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.api.deletePaukstunde(entry.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Paukstunde gelöscht.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFriendlyApiError(
              e,
              fallback: 'Paukstunde konnte nicht gelöscht werden.',
            ),
          ),
        ),
      );
    }
  }

  String _participants(PaukstundenEntryDto entry) {
    if (entry.participants.isEmpty) return 'Keine Teilnehmer';
    return entry.participants
        .map(
          (p) => MemberStatuses.pickerDisplayName(
        displayName: p.displayName,
        memberStatus: p.memberStatus,
      ),
    )
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final entries = data?.entries ?? const <PaukstundenEntryDto>[];

    return AppScaffold(
      title: 'Meine Paukstunden',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        IconButton(
          tooltip: 'Eintragen',
          icon: const Icon(Icons.add_rounded),
          onPressed: _openCreate,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Symbols.swords),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${data?.totalHours ?? 0} Paukstunden',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${data?.entryCount ?? 0} Einträge in der aktuellen Conventsperiode',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Keine Paukstunden eingetragen.'),
              )
            else
              for (final entry in entries)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_note_rounded),
                    title: Text(
                      '${Format.dateOnlyShort(entry.date)} · ${entry.hours} Std.',
                    ),
                    subtitle: Text(_participants(entry)),
                    trailing: _canEdit(entry)
                        ? PopupMenuButton<String>(
                      tooltip: 'Aktionen',
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openEdit(entry);
                        } else if (value == 'delete') {
                          _delete(entry);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Bearbeiten'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Löschen'),
                        ),
                      ],
                    )
                        : null,
                    titleAlignment: ListTileTitleAlignment.center,
                  ),
                ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}