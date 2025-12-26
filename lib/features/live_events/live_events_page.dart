import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/cache/app_cache.dart';
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
  static const _ttlLive = Duration(minutes: 1);
  static const _kLiveEvents = 'liveevents.items';

  bool _loading = true;
  bool _refreshing = false;

  List<LiveEventDto> _items = const [];
  String? _myUserId;
  bool _myUserIdLoading = false;

  Map<String, dynamic> _encodeLive(LiveEventDto e) => {
    'id': e.id,
    'title': e.title,
    'place': e.place,
    'description': e.description,
    'createdAt': e.createdAt,
    'expiresAt': e.expiresAt,
    'createdByUserId': e.createdByUserId,
  };

  LiveEventDto _decodeLive(Object json) =>
      LiveEventDto.fromJson((json as Map).cast<String, dynamic>());

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyUserId();
  }

  Future<void> _loadMyUserId() async {
    if (_myUserIdLoading) return;
    _myUserIdLoading = true;
    try {
      final p = await widget.api.getActivePeriod();
      final bal = await widget.api.getMyBalance(periodId: p.id);
      if (!mounted) return;
      setState(() => _myUserId = bal.userId);
    } catch (_) {
      // ignore
    } finally {
      _myUserIdLoading = false;
    }
  }

  Future<void> _load({bool force = false}) async {
    try {
      final c = await AppCache.I.entryOrLoadPersisted<List<LiveEventDto>>(
        _kLiveEvents,
        decode: (json) => (json as List).map((e) => _decodeLive(e as Object)).toList(growable: false),
      );
      final hasCache = c != null;

      if (hasCache && mounted) {
        final cachedList = List<LiveEventDto>.from(c.value);
        setState(() {
          _items = List<LiveEventDto>.unmodifiable(cachedList);
          _loading = false;
        });

        if (!force && c.isFresh(_ttlLive)) return;
      }

      final showFullSpinner = !hasCache;
      if (mounted) {
        setState(() {
          _loading = showFullSpinner;
          _refreshing = !showFullSpinner;
        });
      }

      try {
        final list = await widget.api.listLiveEvents();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final frozen = List<LiveEventDto>.unmodifiable(list);

        await AppCache.I.setPersisted<List<LiveEventDto>>(
          _kLiveEvents,
          frozen,
          encode: (v) => v.map(_encodeLive).toList(growable: false),
        );

        if (!mounted) return;
        setState(() => _items = frozen);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Live-Events laden fehlgeschlagen: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
            _refreshing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  bool _canEdit(LiveEventDto e, Set<AppRole> roles, String? myUserId) {
    if (roles.contains(AppRole.admin) ||
        roles.contains(AppRole.senior) ||
        roles.contains(AppRole.housekeeping)) {
      return true;
    }
    return myUserId != null && e.createdByUserId == myUserId;
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
          onPressed: _loading ? null : () => _load(force: true),
        ),
        IconButton(
          tooltip: 'Neu',
          icon: const Icon(Icons.add_rounded),
          onPressed: () async {
            await context.push('/live-events/new');
            if (!mounted) return;
            await _load(force: true);
          },
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Aktuell keine Live-Events.'),
              ),
            for (final e in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: const Icon(Icons.group_rounded),
                    title: Text(e.title),
                    subtitle: Text(
                      '${e.place}\nläuft bis: ${Format.dateTimeShort(e.expiresAt)}',
                    ),
                    isThreeLine: true,
                    trailing: _canEdit(e, roles, _myUserId)
                        ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          await context.push('/live-events/${e.id}/edit');
                          if (!mounted) return;
                          await _load(force: true);
                        } else if (v == 'delete') {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Live-Event löschen?'),
                              content: Text('„${e.title}“ wird gelöscht.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Abbrechen'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Löschen'),
                                ),
                              ],
                            ),
                          ) ??
                              false;

                          if (!ok) return;

                          await widget.api.deleteLiveEvent(e.id);

                          await AppCache.I.removePersisted(_kLiveEvents);

                          if (!mounted) return;
                          await _load(force: true);
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
              ),
          ],
        ),
      ),
    );
  }
}
