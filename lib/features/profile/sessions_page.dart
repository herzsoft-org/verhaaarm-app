import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class SessionsPage extends StatefulWidget {
  final ApiClient api;

  const SessionsPage({super.key, required this.api});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  bool _loading = true;
  bool _busy = false;
  List<UserSessionDto> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load(touch: true);
  }

  Future<void> _load({bool touch = false}) async {
    setState(() => _loading = true);

    try {
      if (touch) {
        try {
          await widget.api.touchMySession();
        } catch (_) {
          // Non-critical. Listing sessions should still work.
        }
      }

      final sessions = await widget.api.listMySessions();

      sessions.sort((a, b) {
        if (a.current && !b.current) return -1;
        if (!a.current && b.current) return 1;

        final aRevoked = a.revokedAt != null;
        final bRevoked = b.revokedAt != null;

        if (!aRevoked && bRevoked) return -1;
        if (aRevoked && !bRevoked) return 1;

        return b.lastActiveAt.compareTo(a.lastActiveAt);
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
    if (s.current || s.revokedAt != null || _busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session entfernen?'),
        content: Text(
          'Diese Session wird abgemeldet.\n\n'
              '${_sessionTitle(s)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);

    try {
      await widget.api.revokeMySession(s.id);
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session wurde entfernt.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session konnte nicht entfernt werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sessionTitle(UserSessionDto s) {
    final parts = <String>[
      s.appType,
      if ((s.deviceName ?? '').trim().isNotEmpty) s.deviceName!.trim(),
      if ((s.deviceModel ?? '').trim().isNotEmpty) s.deviceModel!.trim(),
      if ((s.browserName ?? '').trim().isNotEmpty) s.browserName!.trim(),
    ];

    return parts.isEmpty ? 'Unbekannte Session' : parts.join(' · ');
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Sessions',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(touch: true),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                child: Text('Keine Sessions gefunden.'),
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
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_sessionIcon(s)),
                      title: Text(_sessionTitle(s)),
                      subtitle: Text(_osLine(s)),
                      trailing: s.current
                          ? const Chip(
                        label: Text('Aktuell'),
                        avatar: Icon(Icons.check_circle_rounded),
                      )
                          : s.revokedAt != null
                          ? const Chip(
                        label: Text('Widerrufen'),
                        avatar: Icon(Icons.block_rounded),
                      )
                          : null,
                    ),
                    const SizedBox(height: 4),
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
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (!s.current && s.revokedAt == null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _revoke(s),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Session entfernen'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
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