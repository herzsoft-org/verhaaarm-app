import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class AdminUserSessionsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String userId;

  const AdminUserSessionsPage({
    super.key,
    required this.api,
    required this.authStore,
    required this.userId,
  });

  @override
  State<AdminUserSessionsPage> createState() => _AdminUserSessionsPageState();
}

class _AdminUserSessionsPageState extends State<AdminUserSessionsPage> {
  bool _loading = true;
  bool _busy = false;
  List<UserSessionDto> _sessions = const [];

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

      final allSessions = await widget.api.listAdminSessions();
      final sessions = allSessions
          .where((s) => s.userId == widget.userId)
          .toList(growable: false);

      sessions.sort((a, b) {
        if (_isActive(a) && !_isActive(b)) return -1;
        if (!_isActive(a) && _isActive(b)) return 1;

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

  Future<void> _revoke(UserSessionDto s) async {
    if (_busy || s.revokedAt != null) return;

    final isOwnCurrentSession = s.current;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session beenden?'),
        content: Text(
          isOwnCurrentSession
              ? 'Das ist deine aktuelle Session. Wenn du sie beendest, kann dein aktueller Zugriff sofort ungültig werden.\n\n${_sessionTitle(s)}'
              : 'Diese Session wird beendet.\n\n${_sessionTitle(s)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Beenden'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);

    try {
      await widget.api.revokeAdminSession(s.id);

      if (isOwnCurrentSession) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aktuelle Session wurde beendet. Bitte ggf. neu anmelden.'),
          ),
        );
        return;
      }

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session wurde beendet.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session konnte nicht beendet werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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

  String _sessionTitle(UserSessionDto s) {
    final parts = <String>[
      _appTypeLabel(s.appType),
      if ((s.deviceName ?? '').trim().isNotEmpty) s.deviceName!.trim(),
      if ((s.deviceModel ?? '').trim().isNotEmpty) s.deviceModel!.trim(),
      if ((s.browserName ?? '').trim().isNotEmpty) s.browserName!.trim(),
    ];

    return parts.isEmpty ? 'Unbekannte Session' : parts.join(' · ');
  }

  String _appTypeLabel(String value) {
    switch (value.toUpperCase()) {
      case 'ANDROID':
        return 'Android';
      case 'WEB':
        return 'Web';
      default:
        return 'Unbekannt';
    }
  }

  String _osLine(UserSessionDto s) {
    final os = [
      s.osName,
      s.osVersion,
    ].where((v) => (v ?? '').trim().isNotEmpty).join(' ');

    final browser = [
      s.browserName,
      s.browserVersion,
    ].where((v) => (v ?? '').trim().isNotEmpty).join(' ');

    if (os.isNotEmpty && browser.isNotEmpty) return '$os · $browser';
    if (os.isNotEmpty) return os;
    if (browser.isNotEmpty) return browser;
    return '—';
  }

  String _date(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';

    try {
      return Format.dateTimeShort(iso);
    } catch (_) {
      return iso;
    }
  }

  IconData _sessionIcon(UserSessionDto s) {
    if (s.revokedAt != null) return Icons.block_rounded;

    switch (s.appType.toUpperCase()) {
      case 'ANDROID':
        return Icons.phone_android_rounded;
      case 'WEB':
        return Icons.language_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  String _pageTitle() {
    if (_sessions.isEmpty) return 'Nutzer-Sessions';

    final first = _sessions.first;
    final displayName = first.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final username = first.username?.trim();
    if (username != null && username.isNotEmpty) return username;

    return 'Nutzer-Sessions';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _pageTitle(),
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
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (_sessions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Keine Sessions für diesen Nutzer gefunden.'),
                ),
              ),
            for (final s in _sessions)
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        titleAlignment: ListTileTitleAlignment.center,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_sessionIcon(s)),
                        title: Text(_sessionTitle(s)),
                        subtitle: Text(_osLine(s)),
                        trailing: _SessionStatusChip(session: s),
                      ),
                      const SizedBox(height: 4),
                      _InfoLine(label: 'App-Typ', value: _appTypeLabel(s.appType)),
                      _InfoLine(label: 'IP-Adresse', value: _emptyDash(s.ipAddress)),
                      _InfoLine(label: 'Land', value: _emptyDash(s.countryCode)),
                      _InfoLine(label: 'Erstellt', value: _date(s.createdAt)),
                      _InfoLine(
                        label: 'Zuletzt aktiv',
                        value: _date(s.lastActiveAt),
                      ),
                      _InfoLine(label: 'Läuft ab', value: _date(s.expiresAt)),
                      _InfoLine(
                        label: 'Widerrufen',
                        value: s.revokedAt == null ? 'Nein' : _date(s.revokedAt),
                      ),
                      if ((s.userAgent ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          s.userAgent!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (s.revokedAt == null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _revoke(s),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Session beenden'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _emptyDash(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return '—';
    return v;
  }
}

class _SessionStatusChip extends StatelessWidget {
  final UserSessionDto session;

  const _SessionStatusChip({required this.session});

  bool _isExpired(UserSessionDto s) {
    final expiresAt = s.expiresAt;
    if (expiresAt == null || expiresAt.trim().isEmpty) return false;

    try {
      return DateTime.parse(expiresAt).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (session.current) {
      return const Chip(
        label: Text('Aktuell'),
        avatar: Icon(Icons.check_circle_rounded),
      );
    }

    if (session.revokedAt != null) {
      return const Chip(
        label: Text('Widerrufen'),
        avatar: Icon(Icons.block_rounded),
      );
    }

    if (_isExpired(session)) {
      return const Chip(
        label: Text('Abgelaufen'),
        avatar: Icon(Icons.schedule_rounded),
      );
    }

    return const Chip(
      label: Text('Aktiv'),
      avatar: Icon(Icons.circle_rounded),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}