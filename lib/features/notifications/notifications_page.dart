import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../notifications/notification_center.dart';
import '../../push/push_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const NotificationsPage({
    super.key,
    required this.api,
    required this.authStore,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  bool _clearing = false;
  bool _enablingWebPush = false;
  List<NotificationDto> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();

    NotificationCenter.I.refreshUnreadCount();
    if (kIsWeb) {
      NotificationCenter.I.refreshPushStatus();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.listNotifications(limit: 50);
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _items = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(NotificationDto n) async {
    if (n.readAt != null) return;

    setState(() {
      _items = _items
          .map((x) => x.id == n.id ? x.copyWith(readAt: DateTime.now().toUtc()) : x)
          .toList(growable: false);
    });
    NotificationCenter.I.decrementUnread(by: 1);

    try {
      await widget.api.markNotificationRead(n.id);
    } catch (_) {
      NotificationCenter.I.refreshUnreadCount();
    }
  }

  Future<void> _delete(NotificationDto n) async {
    final prev = _items;
    setState(() => _items = _items.where((x) => x.id != n.id).toList(growable: false));

    if (n.readAt == null) NotificationCenter.I.decrementUnread(by: 1);

    try {
      await widget.api.deleteNotification(n.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = prev);
      NotificationCenter.I.refreshUnreadCount();
    }
  }

  Future<void> _clearAll() async {
    if (_clearing) return;
    setState(() => _clearing = true);

    final prev = _items;
    setState(() => _items = const []);
    NotificationCenter.I.resetUnread();

    try {
      await widget.api.clearNotifications();
      debugPrint('Alle löschen: OK');
    } catch (e, st) {
      debugPrint('Alle löschen: FEHLGESCHLAGEN: $e\n$st');
      if (!mounted) return;
      setState(() => _items = prev);
      NotificationCenter.I.refreshUnreadCount();
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _enableWebPush() async {
    if (_enablingWebPush) return;

    setState(() => _enablingWebPush = true);
    try {
      final pm = PushManager(api: widget.api, authStore: widget.authStore);
      await pm.enableWebPushFromButtonClick();
    } finally {
      await NotificationCenter.I.refreshPushStatus();
      if (mounted) setState(() => _enablingWebPush = false);
    }
  }

  void _openFromNotification(NotificationDto n) {
    final data = n.data;
    final type = n.type.toUpperCase();

    final fineId = (data['fineId'] ?? '').trim();
    final taskId = (data['taskId'] ?? '').trim();

    if (taskId.isNotEmpty || type.contains('TASK')) {
      context.push('/tasks');
      return;
    }

    if (fineId.isNotEmpty || type.contains('FINE')) {
      context.push('/my-fines');
      return;
    }
  }

  String _pushStatusLabel(PushStatus status) {
    switch (status) {
      case PushStatus.enabled:
        return 'Web-Benachrichtigungen sind bereits aktiviert';
      case PushStatus.disabled:
        return 'Web-Benachrichtigungen sind noch nicht aktiviert';
      case PushStatus.error:
        return 'Status der Web-Benachrichtigungen konnte nicht geprüft werden';
      case PushStatus.unknown:
        return 'Prüfe Status der Web-Benachrichtigungen ...';
      case PushStatus.unsupported:
        return '';
    }
  }

  Color? _pushStatusColor(BuildContext context, PushStatus status) {
    switch (status) {
      case PushStatus.enabled:
        return Colors.green;
      case PushStatus.disabled:
        return Colors.orange;
      case PushStatus.error:
        return Theme.of(context).colorScheme.error;
      case PushStatus.unknown:
      case PushStatus.unsupported:
        return Theme.of(context).textTheme.bodyMedium?.color;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Benachrichtigungen',
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await NotificationCenter.I.refreshUnreadCount();
          if (kIsWeb) {
            await NotificationCenter.I.refreshPushStatus();
          }
        },
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _items.isEmpty || _clearing ? null : _clearAll,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Alle löschen'),
                  ),
                ],
              ),
            ),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none, size: 48),
                    SizedBox(height: 12),
                    Text('Keine Benachrichtigungen'),
                  ],
                ),
              ),
            if (_items.isNotEmpty)
              ..._items.map((n) {
                final unread = n.readAt == null;

                return Dismissible(
                  key: ValueKey(n.id),
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: const Icon(Icons.delete),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _delete(n),
                  child: ListTile(
                    title: Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
                    ),
                    subtitle: Text(
                      n.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    leading: unread
                        ? const Icon(Icons.circle, size: 10)
                        : const Icon(Icons.circle_outlined, size: 10),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await _markRead(n);
                      _openFromNotification(n);
                    },
                  ),
                );
              }),

            const SizedBox(height: 24),

            if (kIsWeb) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: _enablingWebPush ? null : _enableWebPush,
                  icon: _enablingWebPush
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.notifications_active),
                  label: Text(
                    _enablingWebPush
                        ? 'Aktiviere Web-Benachrichtigungen ...'
                        : 'Web-Benachrichtigungen aktivieren',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: StreamBuilder<PushStatus>(
                  stream: NotificationCenter.I.pushStatusStream,
                  initialData: NotificationCenter.I.pushStatus,
                  builder: (context, snapshot) {
                    final status = snapshot.data ?? PushStatus.unknown;
                    final label = _pushStatusLabel(status);
                    if (label.isEmpty) return const SizedBox.shrink();

                    return Text(
                      label,
                      style: TextStyle(
                        color: _pushStatusColor(context, status),
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}