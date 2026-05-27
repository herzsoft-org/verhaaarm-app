import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notifications/notification_center.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final RefreshCallback? onRefresh;
  final String? locationOverride;

  final bool showNotificationButton;
  final bool showProfileButton;
  final bool showBottomNavigationBar;

  const AppScaffold({
    super.key,
    required this.title,
    this.titleWidget,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.onRefresh,
    this.locationOverride,
    this.showNotificationButton = true,
    this.showProfileButton = true,
    this.showBottomNavigationBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final location =
        locationOverride ?? GoRouterState.of(context).uri.toString();
    final isOnNotifications =
        location == '/notifications' || location.startsWith('/notifications/');

    final scaffoldBody = _AppBodyWithNotificationReminder(
      body: onRefresh == null
          ? body
          : RefreshIndicator(onRefresh: onRefresh!, child: body),
      enabled: showNotificationButton || isOnNotifications,
    );

    return Scaffold(
      appBar: AppBar(
        title: titleWidget ?? Text(title),
        actions: [
          ...(actions ?? const []),

          if (showNotificationButton && !isOnNotifications)
            _NotificationBell(onTap: () => context.push('/notifications')),
        ],
      ),
      body: scaffoldBody,
      bottomNavigationBar: showBottomNavigationBar
          ? MainNavigationBar(
              selectedIndex: mainTabIndexForLocation(location),
              onDestinationSelected: (index) {
                final target = mainTabLocationForIndex(index);
                if (location == target) return;
                context.go(target);
              },
            )
          : null,
      floatingActionButton: floatingActionButton,
    );
  }
}

int mainTabIndexForLocation(String location) {
  final path = _pathForTabLocation(location);
  if (_isActionsTabLocation(path)) return 1;
  if (path == '/profile' || path.startsWith('/profile/')) return 2;
  return 0;
}

String _pathForTabLocation(String location) {
  final parsed = Uri.tryParse(location);
  final path = parsed?.path ?? location;
  return path.isEmpty ? '/' : path;
}

bool _isActionsTabLocation(String path) {
  if (path == '/actions' || path.startsWith('/actions/')) return true;

  return _actionsTabRootPaths.any(
    (root) => path == root || path.startsWith('$root/'),
  );
}

const Set<String> _actionsTabRootPaths = {
  '/tasks',
  '/my-fine-suggestions',
  '/suggestions',
  '/my-fines',
  '/fines',
  '/paukstunden',
  '/office',
  '/convent-protocols',
  '/legal-documents',
};

String mainTabLocationForIndex(int index) {
  return switch (index) {
    0 => '/home',
    1 => '/actions',
    2 => '/profile',
    _ => '/home',
  };
}

class MainNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const MainNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Start',
        ),
        NavigationDestination(
          icon: Icon(Icons.apps_outlined),
          selectedIcon: Icon(Icons.apps_rounded),
          label: 'Aktionen',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profil',
        ),
      ],
    );
  }
}

class _AppBodyWithNotificationReminder extends StatelessWidget {
  final Widget body;
  final bool enabled;

  const _AppBodyWithNotificationReminder({
    required this.body,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !enabled) return body;

    return Column(
      children: [
        StreamBuilder<PushStatus>(
          stream: NotificationCenter.I.pushStatusStream,
          initialData: NotificationCenter.I.pushStatus,
          builder: (context, snapshot) {
            return _WebNotificationReminder(
              status: snapshot.data ?? PushStatus.unknown,
              location: GoRouterState.of(context).uri.toString(),
            );
          },
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _WebNotificationReminder extends StatefulWidget {
  final PushStatus status;
  final String location;

  const _WebNotificationReminder({
    required this.status,
    required this.location,
  });

  @override
  State<_WebNotificationReminder> createState() =>
      _WebNotificationReminderState();
}

class _WebNotificationReminderState extends State<_WebNotificationReminder> {
  static const _prefKey = 'webNotificationReminder.dismissedDate';

  bool _ready = false;
  bool _dismissedToday = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _WebNotificationReminder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _load();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (!mounted) return;
    setState(() {
      _dismissedToday = prefs.getString(_prefKey) == today;
      _ready = true;
    });
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _todayKey());
    if (!mounted) return;
    setState(() => _dismissedToday = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _dismissedToday || widget.status != PushStatus.disabled) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final text = widget.location == '/notifications'
        ? 'Benachrichtigungen sind im Browser deaktiviert. Klicke auf den Button unten, um sie zu aktivieren.'
        : widget.location == '/home'
        ? 'Benachrichtigungen sind im Browser deaktiviert. Klicke auf die Glocke oben, um sie zu aktivieren und Arbeitsaufträge und Veranstaltungen nicht zu verpassen.'
        : 'Benachrichtigungen sind im Browser deaktiviert. Aktiviere sie über die Glocke oben, damit du Arbeitsaufträge und Veranstaltungen nicht verpasst.';
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              Icons.notifications_off_rounded,
              color: cs.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: cs.onSecondaryContainer),
              ),
            ),
            IconButton(
              tooltip: 'Schließen',
              onPressed: _dismiss,
              icon: Icon(Icons.close_rounded, color: cs.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBell extends StatefulWidget {
  final VoidCallback onTap;

  const _NotificationBell({required this.onTap});

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  late final StreamSubscription<int> _sub;
  int _unread = NotificationCenter.I.unread;

  @override
  void initState() {
    super.initState();
    _sub = NotificationCenter.I.unreadStream.listen((v) {
      if (!mounted) return;
      setState(() => _unread = v);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: widget.onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_rounded),
          if (_unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  _unread > 99 ? '99+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
