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
    final refresh = authStore.refreshToken;
    await authStore.clear();

    if (refresh != null) {
      try {
        await api.logoutOnServer(refresh);
      } catch (_) {
        // bewusst ignoriert (hobby app)
      }
    }

    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final username = authStore.username ?? '—';

    return AppScaffold(
      title: 'Profil',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_rounded),
              title: const Text('Benutzername'),
              subtitle: Text(username),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Abmelden'),
            ),
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: 0.7,
            child: Text(
              'Verhåårm\nFrontend: herz.moe',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
