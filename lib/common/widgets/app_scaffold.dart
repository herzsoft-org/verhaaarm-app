import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...(actions ?? const []),
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
