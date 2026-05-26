import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/api_error_text.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

class MyPaukstundenPage extends StatefulWidget {
  final ApiClient api;

  const MyPaukstundenPage({super.key, required this.api});

  @override
  State<MyPaukstundenPage> createState() => _MyPaukstundenPageState();
}

class _MyPaukstundenPageState extends State<MyPaukstundenPage> {
  bool _loading = true;
  PaukstundenListDto? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await widget.api.getMyCurrentPaukstunden();
      if (!mounted) return;
      setState(() => _data = data);
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
                          const Icon(Icons.gavel_rounded),
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
                  if ((data?.entries ?? const <PaukstundenEntryDto>[]).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Keine Paukstunden eingetragen.'),
                    )
                  else
                    for (final entry in data!.entries)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_note_rounded),
                          title: Text(
                            '${Format.dateOnlyShort(entry.date)} · ${entry.hours} Std.',
                          ),
                          subtitle: Text(_participants(entry)),
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
