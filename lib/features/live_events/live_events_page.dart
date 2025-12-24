import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class LiveEventsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const LiveEventsPage({super.key, required this.api, required this.authStore});

  @override
  State<LiveEventsPage> createState() => _LiveEventsPageState();
}

class _LiveEventsPageState extends State<LiveEventsPage> {
  bool _loading = true;
  List<LiveEventDto> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.listLiveEvents();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Live-Events laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _canEdit(LiveEventDto e, Set<AppRole> roles, String? myUserId) {
    if (roles.contains(AppRole.admin) || roles.contains(AppRole.senior) || roles.contains(AppRole.housekeeping)) {
      return true;
    }
    return myUserId != null && e.createdByUserId == myUserId;
    // backend rules: creator OR SENIOR/HOUSEKEEPING/ADMIN
  }

  Future<String?> _getMyUserId() async {
    try {
      final p = await widget.api.getActivePeriod();
      final bal = await widget.api.getMyBalance(periodId: p.id);
      return bal.userId;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);

    return AppScaffold(
      title: 'Wo geht was?',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        IconButton(
          tooltip: 'Neu',
          icon: const Icon(Icons.add_rounded),
          onPressed: () async {
            await context.push('/live-events/new');
            if (!mounted) return;
            await _load();
          },
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Aktuell keine Live-Events.'),
              ),
            ..._items.map((e) {
              return FutureBuilder<String?>(
                future: _getMyUserId(),
                builder: (context, snap) {
                  final myId = snap.data;
                  final canEdit = _canEdit(e, roles, myId);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.group_rounded),
                        title: Text(e.title),
                        subtitle: Text('${e.place}\nläuft bis: ${Format.dateTimeShort(e.expiresAt)}'),
                        isThreeLine: true,
                        trailing: canEdit
                            ? PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              await context.push('/live-events/${e.id}/edit');
                              if (!mounted) return;
                              await _load();
                            }
                            else if (v == 'delete') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Live-Event löschen?'),
                                  content: Text('„${e.title}“ wird gelöscht.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
                                  ],
                                ),
                              ) ??
                                  false;
                              if (!ok) return;
                              await widget.api.deleteLiveEvent(e.id);
                              if (!mounted) return;
                              await _load();
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                            PopupMenuItem(value: 'delete', child: Text('Löschen')),
                          ],
                        )
                            : null,
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
