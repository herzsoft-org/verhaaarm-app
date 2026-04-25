import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class SessionStatsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const SessionStatsPage({
    super.key,
    required this.api,
    required this.authStore,
  });

  @override
  State<SessionStatsPage> createState() => _SessionStatsPageState();
}

class _SessionStatsPageState extends State<SessionStatsPage> {
  bool _loading = true;
  bool _usersBusy = false;

  SessionStatsDto? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!roles.contains(AppRole.admin)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Berechtigung.')),
        );
        return;
      }

      final stats = await widget.api.getSessionStats();

      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session-Statistik konnte nicht geladen werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _sum(List<SessionStatsBucketDto> rows) {
    var total = 0;
    for (final r in rows) {
      total += r.count;
    }
    return total;
  }

  Future<void> _openUsersForPeriod(_StatsPeriod period) async {
    if (_usersBusy) return;

    setState(() => _usersBusy = true);

    try {
      final users = await _loadUsersForPeriod(period);

      users.sort((a, b) {
        final ao = a.lastOnlineAt ?? '';
        final bo = b.lastOnlineAt ?? '';
        final c = bo.compareTo(ao);
        if (c != 0) return c;

        final ad = a.displayName.trim().toLowerCase();
        final bd = b.displayName.trim().toLowerCase();
        return ad.compareTo(bd);
      });

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _OnlineUsersSheet(
          title: _periodUsersTitle(period),
          users: users,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nutzer konnten nicht geladen werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _usersBusy = false);
    }
  }

  Future<List<UserDto>> _loadUsersForPeriod(_StatsPeriod period) async {
    switch (period) {
      case _StatsPeriod.week:
        return widget.api.listUsersAdmin(online: 'week');

      case _StatsPeriod.month:
        return widget.api.listUsersAdmin(online: 'month');

      case _StatsPeriod.year:
        final users = await widget.api.listUsersAdmin();
        final now = DateTime.now();
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year + 1, 1, 1);

        return users.where((u) {
          final raw = u.lastOnlineAt;
          if (raw == null || raw.trim().isEmpty) return false;

          final dt = DateTime.tryParse(raw)?.toLocal();
          if (dt == null) return false;

          return !dt.isBefore(start) && dt.isBefore(end);
        }).toList(growable: false);
    }
  }

  String _periodUsersTitle(_StatsPeriod period) {
    switch (period) {
      case _StatsPeriod.week:
        return 'Online diese Woche';
      case _StatsPeriod.month:
        return 'Online diesen Monat';
      case _StatsPeriod.year:
        return 'Online dieses Jahr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    return AppScaffold(
      title: 'Session-Statistik',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_usersBusy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          if (stats == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Keine Statistik verfügbar.'),
              ),
            )
          else ...[
            _StatsCard(
              title: 'Diese Woche',
              total: _sum(stats.week),
              rows: stats.week,
              onTap: () => _openUsersForPeriod(_StatsPeriod.week),
            ),
            const SizedBox(height: 12),
            _StatsCard(
              title: 'Dieser Monat',
              total: _sum(stats.month),
              rows: stats.month,
              onTap: () => _openUsersForPeriod(_StatsPeriod.month),
            ),
            const SizedBox(height: 12),
            _StatsCard(
              title: 'Dieses Jahr',
              total: _sum(stats.year),
              rows: stats.year,
              onTap: () => _openUsersForPeriod(_StatsPeriod.year),
            ),
          ],
        ],
      ),
    );
  }
}

enum _StatsPeriod {
  week,
  month,
  year,
}

class _StatsCard extends StatelessWidget {
  final String title;
  final int total;
  final List<SessionStatsBucketDto> rows;
  final VoidCallback onTap;

  const _StatsCard({
    required this.title,
    required this.total,
    required this.rows,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        if (c != 0) return c;

        final app = a.appType.compareTo(b.appType);
        if (app != 0) return app;

        return a.browserName.compareTo(b.browserName);
      });

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 4),
              Text('Aktive Sessions: $total'),
              const SizedBox(height: 4),
              Text(
                'Antippen, um Nutzer zu sehen',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (sorted.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Keine Daten.'),
                )
              else
                for (final r in sorted)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r.appType == 'ANDROID'
                          ? Icons.phone_android_rounded
                          : r.appType == 'WEB'
                          ? Icons.language_rounded
                          : Icons.devices_other_rounded,
                    ),
                    title: Text('${r.appType} · ${r.browserName}'),
                    trailing: Text(
                      '${r.count}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineUsersSheet extends StatelessWidget {
  final String title;
  final List<UserDto> users;

  const _OnlineUsersSheet({
    required this.title,
    required this.users,
  });

  String _date(String? iso) {
    if (iso == null || iso.trim().isEmpty) return 'nie online';

    try {
      return Format.dateTimeShort(iso);
    } catch (_) {
      return iso;
    }
  }

  String _roleLabel(UserDto u) {
    if (u.roles.isEmpty) return '—';

    switch (u.roles.first.toUpperCase()) {
      case 'SENIOR':
        return 'Sprecher';
      case 'HOUSEKEEPING':
        return 'Schmuckwart';
      case 'MEMBER':
        return 'Mitglied';
      case 'ADMIN':
        return 'Admin';
      case 'TREASURER':
        return 'Kassenwart';
      default:
        return u.roles.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      '${users.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              if (users.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Keine Nutzer gefunden.'),
                  ),
                )
              else
                for (final u in users)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        u.disabled ? Icons.block_rounded : Icons.person_rounded,
                      ),
                      title: Text('${u.displayName} (${u.username})'),
                      subtitle: Text(
                        'Rolle: ${_roleLabel(u)}'
                            '\nZuletzt online: ${_date(u.lastOnlineAt)}'
                            '${u.disabled ? '\nDeaktiviert' : ''}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}