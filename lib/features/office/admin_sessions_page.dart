import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class AdminSessionsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const AdminSessionsPage({
    super.key,
    required this.api,
    required this.authStore,
  });

  @override
  State<AdminSessionsPage> createState() => _AdminSessionsPageState();
}

class _AdminSessionsPageState extends State<AdminSessionsPage> {
  bool _loading = true;
  List<UserSessionDto> _sessions = const [];

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

      final sessions = await widget.api.listAdminSessions();

      sessions.sort((a, b) {
        final c = (b.lastActiveAt ?? '').compareTo(a.lastActiveAt ?? '');
        if (c != 0) return c;
        return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
      });

      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sessions konnten nicht geladen werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isActive(UserSessionDto s) {
    if (s.revokedAt != null) return false;

    final expiresAt = s.expiresAt;
    if (expiresAt == null || expiresAt.trim().isEmpty) return true;

    try {
      return DateTime.parse(expiresAt).isAfter(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  String _userKey(UserSessionDto s) {
    final userId = s.userId;
    if (userId != null && userId.trim().isNotEmpty) return userId;
    return 'unknown:${s.username ?? s.displayName ?? s.id}';
  }

  String _userName(_AdminSessionUserGroup g) {
    final displayName = g.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final username = g.username?.trim();
    if (username != null && username.isNotEmpty) return username;

    return 'Unbekannter Nutzer';
  }

  String _date(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';

    try {
      return Format.dateTimeShort(iso);
    } catch (_) {
      return iso;
    }
  }

  List<_AdminSessionUserGroup> _groups() {
    final map = <String, List<UserSessionDto>>{};

    for (final s in _sessions.where(_isActive)) {
      map.putIfAbsent(_userKey(s), () => <UserSessionDto>[]).add(s);
    }

    final groups = map.entries.map((entry) {
      final sessions = entry.value;
      sessions.sort((a, b) {
        final c = (b.lastActiveAt ?? '').compareTo(a.lastActiveAt ?? '');
        if (c != 0) return c;
        return (b.createdAt ?? '').compareTo(a.createdAt ?? '');
      });

      final first = sessions.first;

      return _AdminSessionUserGroup(
        userId: first.userId,
        username: first.username,
        displayName: first.displayName,
        activeSessions: sessions,
      );
    }).toList();

    groups.sort((a, b) {
      final c = (b.latestLastActiveAt ?? '').compareTo(a.latestLastActiveAt ?? '');
      if (c != 0) return c;

      return _userName(a).toLowerCase().compareTo(_userName(b).toLowerCase());
    });

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();

    return AppScaffold(
      title: 'Aktive Sessions',
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
                    const Icon(Icons.devices_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${groups.length} aktive ${groups.length == 1 ? 'Nutzer' : 'Nutzer'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Keine aktiven Sessions gefunden.'),
                ),
              )
            else
              for (final g in groups)
                Card(
                  child: ListTile(
                    titleAlignment: ListTileTitleAlignment.center,
                    leading: const Icon(Icons.person_rounded),
                    title: Text(_userName(g)),
                    subtitle: Text(
                      [
                        if ((g.username ?? '').trim().isNotEmpty)
                          'Username: ${g.username}',
                        '${g.activeSessions.length} aktive ${g.activeSessions.length == 1 ? 'Session' : 'Sessions'}',
                        'Zuletzt aktiv: ${_date(g.latestLastActiveAt)}',
                      ].join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: g.userId == null
                        ? null
                        : () => context.push('/office/sessions/users/${g.userId}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _AdminSessionUserGroup {
  final String? userId;
  final String? username;
  final String? displayName;
  final List<UserSessionDto> activeSessions;

  const _AdminSessionUserGroup({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.activeSessions,
  });

  String? get latestLastActiveAt {
    if (activeSessions.isEmpty) return null;
    return activeSessions.first.lastActiveAt;
  }
}