import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/cache/app_cache.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import 'live_event_reactions.dart';

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
  final Set<String> _pendingReactions = <String>{};

  Map<String, dynamic> _encodeLive(LiveEventDto e) => e.toJson();

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
      await widget.api.getActivePeriod(); // optional
      final bal = await widget.api.getMyBalance();
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
        decode: (json) => (json as List)
            .map((e) => _decodeLive(e as Object))
            .toList(growable: false),
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

  Set<LiveEventReactionType> _pendingTypesFor(String liveEventId) {
    return LiveEventReactionType.values
        .where(
          (type) => _pendingReactions.contains(_reactionKey(liveEventId, type)),
        )
        .toSet();
  }

  String _reactionKey(String liveEventId, LiveEventReactionType type) {
    return '$liveEventId:${type.apiValue}';
  }

  Future<void> _toggleReaction(
    LiveEventDto event,
    LiveEventReactionType type,
  ) async {
    final key = _reactionKey(event.id, type);
    if (_pendingReactions.contains(key)) return;

    setState(() => _pendingReactions.add(key));

    try {
      final result = await widget.api.toggleLiveEventReaction(
        liveEventId: event.id,
        type: type,
      );

      final updated =
          result.event ??
          event.copyWith(reactions: result.summary ?? event.reactions);
      final next = _items
          .map((item) => item.id == event.id ? updated : item)
          .toList(growable: false);
      final frozen = List<LiveEventDto>.unmodifiable(next);

      await AppCache.I.setPersisted<List<LiveEventDto>>(
        _kLiveEvents,
        frozen,
        encode: (v) => v.map(_encodeLive).toList(growable: false),
      );

      if (!mounted) return;
      setState(() => _items = frozen);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reaktion fehlgeschlagen: $e')));
    } finally {
      if (mounted) {
        setState(() => _pendingReactions.remove(key));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = widget.authStore.currentRoles;
    final cs = Theme.of(context).colorScheme;

    return AppScaffold(
      title: 'Wo geht was?',
      showNotificationButton: false,
      showProfileButton: false,
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
                          onTap: () async {
                            await context.push(
                              '/live-events/${e.id}',
                              extra: e,
                            );
                            if (!mounted) return;
                            await _load(force: true);
                          },
                          titleAlignment: ListTileTitleAlignment.center,
                          // CHANGED: remove big leading icon; icons are now inline before text
                          leading: null,
                          title: Row(
                            children: [
                              Icon(
                                Icons.campaign_rounded,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(e.title)),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((e.place ?? '').trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.place_rounded,
                                        size: 18,
                                        color: cs.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(e.place ?? '')),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'läuft bis: ${Format.dateTimeShort(e.expiresAt)}',
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: LiveEventReactionButtons(
                                  reactions: e.reactions,
                                  pendingTypes: _pendingTypesFor(e.id),
                                  onToggle: (type) => _toggleReaction(e, type),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: _canEdit(e, roles, _myUserId)
                              ? PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'edit') {
                                      await context.push(
                                        '/live-events/${e.id}/edit',
                                      );
                                      if (!mounted) return;
                                      await _load(force: true);
                                    } else if (v == 'delete') {
                                      final ok =
                                          await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                'Live-Event löschen?',
                                              ),
                                              content: Text(
                                                '„${e.title}“ wird gelöscht.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text(
                                                    'Abbrechen',
                                                  ),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text('Löschen'),
                                                ),
                                              ],
                                            ),
                                          ) ??
                                          false;

                                      if (!ok) return;

                                      await widget.api.deleteLiveEvent(e.id);

                                      await AppCache.I.removePersisted(
                                        _kLiveEvents,
                                      );

                                      if (!mounted) return;
                                      await _load(force: true);
                                    }
                                  },
                                  itemBuilder: (_) => const [
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
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
