import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/widgets/app_scaffold.dart';

class ProfilePage extends StatelessWidget {
  final ApiClient api;
  final AuthStore authStore;

  const ProfilePage({super.key, required this.api, required this.authStore});

  Future<void> _logout(BuildContext context) async {
    final rt = authStore.refreshToken;
    if (rt != null && rt.isNotEmpty) {
      try {
        await api.logoutOnServer(rt);
      } catch (_) {
        // ignore
      }
    }
    await authStore.clear();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Profil',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(authStore.isLoggedIn ? 'Angemeldet' : 'Nicht angemeldet'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Abmelden'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Verhåårm\n© herz',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
