import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/api_error_text.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

class FechtwartPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const FechtwartPage({super.key, required this.api, required this.authStore});

  @override
  State<FechtwartPage> createState() => _FechtwartPageState();
}

class _FechtwartPageState extends State<FechtwartPage> {
  bool _loading = true;
  bool _showPast = false;
  PaukstundenSummaryDto? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summary = await widget.api.getCurrentPaukstundenSummary();

      if (!mounted) return;
      setState(() => _summary = summary);
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
    final changed = await context.push<bool>(
      '/office/fechtwart/paukstunden/new',
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  Future<void> _openEdit(PaukstundenEntryDto entry) async {
    final changed = await context.push<bool>(
      '/office/fechtwart/paukstunden/${entry.id}/edit',
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
    if (entry.participants.isEmpty) return '';
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
    final roles = widget.authStore.currentRoles;
    if (!Roles.canManagePaukstunden(roles)) {
      return const AppScaffold(
        title: 'Fechtwart',
        showNotificationButton: false,
        showProfileButton: false,
        body: Center(child: Text('Kein Zugriff.')),
      );
    }

    final summary = _summary;
    final users = summary?.users ?? const <PaukstundenUserSummaryDto>[];

    return AppScaffold(
      title: 'Fechtwart',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        IconButton(
          tooltip: 'Paukstunde eintragen',
          icon: const Icon(Icons.add_rounded),
          onPressed: _openCreate,
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add_rounded),
      ),
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
                                  summary?.periodLabel?.trim().isNotEmpty ==
                                          true
                                      ? summary!.periodLabel!
                                      : 'Aktuelle Conventsperiode',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${users.length} Nutzer mit Paukstundenübersicht',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (users.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Keine Paukstunden vorhanden.'),
                    )
                  else
                    for (final user in users)
                      Card(
                        child: ExpansionTile(
                          leading: const Icon(Icons.person_rounded),
                          title: Text(
                            user.displayName.isEmpty
                                ? user.username
                                : user.displayName,
                          ),
                          subtitle: Text(
                            '${user.totalHours} Paukstunden'
                            '${user.memberStatus.isEmpty ? '' : ' · ${MemberStatuses.label(user.memberStatus)}'}',
                          ),
                          children: [
                            if (user.entries.isEmpty)
                              const ListTile(
                                title: Text('Keine Eintragsdetails verfügbar.'),
                              )
                            else
                              for (final entry in user.entries)
                                ListTile(
                                  leading: const Icon(Icons.event_note_rounded),
                                  title: Text(
                                    '${Format.dateOnlyShort(entry.date)} · ${entry.hours} Std.',
                                  ),
                                  subtitle: Text(_participants(entry)),
                                  trailing: PopupMenuButton<String>(
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
                                  ),
                                  titleAlignment: ListTileTitleAlignment.center,
                                ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showPast = !_showPast),
                    icon: Icon(
                      _showPast
                          ? Icons.expand_less_rounded
                          : Icons.history_rounded,
                    ),
                    label: Text(
                      _showPast
                          ? 'Vergangene ausblenden'
                          : 'Vergangene Conventsperioden anzeigen',
                    ),
                  ),
                  if (_showPast)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 12, 8, 24),
                      child: Text(
                        'Für vergangene Conventsperioden stellt das Backend noch keine Daten bereit.',
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
