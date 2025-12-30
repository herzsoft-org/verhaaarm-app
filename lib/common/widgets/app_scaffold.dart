import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../notifications/notification_center.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isOnProfile = location == '/profile' || location.startsWith('/profile/');
    final isOnNotifications = location == '/notifications' || location.startsWith('/notifications/');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...(actions ?? const []),

          // Bell (hide on notifications page itself)
          if (!isOnNotifications)
            _NotificationBell(
              onTap: () => context.push('/notifications'),
            ),

          if (!isOnProfile)
            IconButton(
              tooltip: 'Profil',
              icon: const Icon(Icons.person_rounded),
              onPressed: () => context.push('/profile'),
            ),
        ],
      ),
      body: body,
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
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
