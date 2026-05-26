import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
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

  SessionStatsDto? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final roles = widget.authStore.currentRoles;
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
        SnackBar(
          content: Text('Session-Statistik konnte nicht geladen werden: $e'),
        ),
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

  List<SessionStatsBucketDto> _activeRows(SessionStatsDto stats) {
    // Backend hard-deletes revoked sessions after a short time now.
    // The old week/month/year buckets therefore effectively contain the same
    // active-session snapshot. Use one bucket as the source of truth.
    if (stats.week.isNotEmpty) return stats.week;
    if (stats.month.isNotEmpty) return stats.month;
    return stats.year;
  }

  List<_SessionAppGroup> _groupByAppType(List<SessionStatsBucketDto> rows) {
    var android = 0;
    var web = 0;
    var unknown = 0;

    for (final r in rows) {
      switch (r.appType.toUpperCase()) {
        case 'ANDROID':
          android += r.count;
          break;
        case 'WEB':
          web += r.count;
          break;
        default:
          unknown += r.count;
          break;
      }
    }

    final groups = [
      _SessionAppGroup(
        label: 'Android',
        appType: 'ANDROID',
        count: android,
        icon: Icons.phone_android_rounded,
      ),
      _SessionAppGroup(
        label: 'Web',
        appType: 'WEB',
        count: web,
        icon: Icons.language_rounded,
      ),
      _SessionAppGroup(
        label: 'Unbekannt',
        appType: 'UNKNOWN',
        count: unknown,
        icon: Icons.devices_other_rounded,
      ),
    ];

    groups.sort((a, b) {
      final c = b.count.compareTo(a.count);
      if (c != 0) return c;
      return a.label.compareTo(b.label);
    });

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    return AppScaffold(
      title: 'Session-Statistik',
      showNotificationButton: false,
      showProfileButton: false,
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
          if (stats == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Keine Statistik verfügbar.'),
              ),
            )
          else
            _ActiveSessionsCard(
              total: _sum(_activeRows(stats)),
              groups: _groupByAppType(_activeRows(stats)),
              rows: _activeRows(stats),
              onTap: () => context.push('/office/sessions'),
            ),
        ],
      ),
    );
  }
}

class _SessionAppGroup {
  final String label;
  final String appType;
  final int count;
  final IconData icon;

  const _SessionAppGroup({
    required this.label,
    required this.appType,
    required this.count,
    required this.icon,
  });
}

class _ActiveSessionsCard extends StatelessWidget {
  final int total;
  final List<_SessionAppGroup> groups;
  final List<SessionStatsBucketDto> rows;
  final VoidCallback onTap;

  const _ActiveSessionsCard({
    required this.total,
    required this.groups,
    required this.rows,
    required this.onTap,
  });

  String _percent(int count) {
    if (total <= 0) return '0 %';
    final value = count * 100 / total;
    if (value == value.roundToDouble()) {
      return '${value.round()} %';
    }
    return '${value.toStringAsFixed(1)} %';
  }

  String _appTypeLabel(String value) {
    switch (value.toUpperCase()) {
      case 'ANDROID':
        return 'Android App';
      case 'WEB':
        return 'Web';
      default:
        return 'Unbekannt';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final colors = <String, Color>{
      'ANDROID': colorScheme.primary,
      'WEB': colorScheme.secondary,
      'UNKNOWN': colorScheme.tertiary,
    };

    final sortedRows = [...rows]
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        if (c != 0) return c;

        final app = a.appType.compareTo(b.appType);
        if (app != 0) return app;

        return a.detail.compareTo(b.detail);
      });

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.devices_rounded,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Aktive Sessions',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$total aktive ${total == 1 ? 'Session' : 'Sessions'}',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'Nach Gerätetyp gruppiert',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _SessionDistributionBar(
                total: total,
                groups: groups,
                colors: colors,
              ),
              const SizedBox(height: 10),
              for (final g in groups)
                if (g.count > 0)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      g.icon,
                      color: colors[g.appType],
                    ),
                    title: Text(g.label),
                    subtitle: Text(_percent(g.count)),
                    trailing: Text(
                      '${g.count}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
              if (total == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text('Keine aktiven Sessions.'),
                )
              else ...[
                const Divider(height: 20),
                Text(
                  'Details',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final r in sortedRows)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r.appType == 'ANDROID'
                          ? Icons.phone_android_rounded
                          : r.appType == 'WEB'
                          ? Icons.language_rounded
                          : Icons.devices_other_rounded,
                    ),
                    title: Text('${_appTypeLabel(r.appType)} · ${r.detail}'),
                    trailing: Text(
                      '${r.count}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionDistributionBar extends StatelessWidget {
  final int total;
  final List<_SessionAppGroup> groups;
  final Map<String, Color> colors;

  const _SessionDistributionBar({
    required this.total,
    required this.groups,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (total <= 0) {
      return Container(
        height: 14,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (final g in groups)
              if (g.count > 0)
                Expanded(
                  flex: g.count,
                  child: ColoredBox(
                    color: colors[g.appType] ??
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
