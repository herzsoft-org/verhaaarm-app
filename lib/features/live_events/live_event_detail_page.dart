import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import 'live_event_reactions.dart';

class LiveEventDetailPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String liveEventId;
  final LiveEventDto? initialEvent;
  final LiveEventReactionType? initialReactionType;

  const LiveEventDetailPage({
    super.key,
    required this.api,
    required this.authStore,
    required this.liveEventId,
    this.initialEvent,
    this.initialReactionType,
  });

  @override
  State<LiveEventDetailPage> createState() => _LiveEventDetailPageState();
}

class _LiveEventDetailPageState extends State<LiveEventDetailPage> {
  LiveEventDto? _event;
  bool _loading = true;
  LiveEventReactionType? _pendingInitialReaction;
  final Set<LiveEventReactionType> _pendingReactions =
      <LiveEventReactionType>{};

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _loading = widget.initialEvent == null;
    _pendingInitialReaction = widget.initialReactionType;
    _load();
  }

  Future<void> _load() async {
    try {
      final event = await widget.api.getLiveEvent(widget.liveEventId);
      if (!mounted) return;
      setState(() {
        _event = event;
        _loading = false;
      });
      await _toggleInitialReactionIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Live-Event laden fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _toggleReaction(LiveEventReactionType type) async {
    final event = _event;
    if (event == null || _pendingReactions.contains(type)) return;

    setState(() => _pendingReactions.add(type));
    try {
      final result = await widget.api.toggleLiveEventReaction(
        liveEventId: event.id,
        type: type,
      );

      final updated = result.event;
      if (updated != null) {
        if (!mounted) return;
        setState(() => _event = updated);
      } else {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reaktion fehlgeschlagen: $e')));
    } finally {
      if (mounted) {
        setState(() => _pendingReactions.remove(type));
      }
    }
  }

  Future<void> _toggleInitialReactionIfNeeded() async {
    final type = _pendingInitialReaction;
    if (type == null) return;
    _pendingInitialReaction = null;

    await _toggleReaction(type);
    if (!mounted) return;
    context.go('/live-events/${widget.liveEventId}');
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final cs = Theme.of(context).colorScheme;

    return AppScaffold(
      title: 'Live-Event',
      showNotificationButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading && event == null
          ? const Center(child: CircularProgressIndicator())
          : event == null
          ? const Center(child: Text('Live-Event nicht gefunden.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.campaign_rounded, color: cs.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  event.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          if ((event.place ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.place_rounded,
                                  size: 20,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(event.place ?? '')),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'läuft bis: ${Format.dateTimeShort(event.expiresAt)}',
                          ),
                          if ((event.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(event.description ?? ''),
                          ],
                          const SizedBox(height: 16),
                          LiveEventReactionButtons(
                            reactions: event.reactions,
                            pendingTypes: _pendingReactions,
                            onToggle: _toggleReaction,
                            emphaticLabels: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ReactionUsersSection(
                    title: 'Prost!',
                    users: event.reactionUsers?.prost ?? const [],
                  ),
                  const SizedBox(height: 8),
                  _ReactionUsersSection(
                    title: 'Ich komme!',
                    users: event.reactionUsers?.ichKomme ?? const [],
                  ),
                ],
              ),
            ),
    );
  }
}

class _ReactionUsersSection extends StatelessWidget {
  final String title;
  final List<LiveEventReactionUserDto> users;

  const _ReactionUsersSection({required this.title, required this.users});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (users.isEmpty)
              Text(
                'Noch niemand',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final user in users)
                    Chip(
                      avatar: CircleAvatar(
                        child: Text(_initials(user.displayName)),
                      ),
                      label: Text(user.displayName),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _initials(String displayName) {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}
