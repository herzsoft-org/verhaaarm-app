import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class UsersPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const UsersPage({super.key, required this.api, required this.authStore});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  bool _loading = true;

  // Backend currently crashes on /users?active=false (500).
  // Until backend supports listing disabled users properly, we always request active=true.
  List<UserDto> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!Roles.canManageUsers(roles)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Berechtigung.')),
        );
        return;
      }

      // IMPORTANT: Always request active users (Swagger requires active param; backend should treat it as "active=true").
      final users = await widget.api.listUsersFull(active: true);

      // Sort by username
      users.sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));

      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nutzer laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final canCreate = Roles.canManageUsers(roles);

    return AppScaffold(
      title: 'Nutzer',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        if (canCreate)
          IconButton(
            tooltip: 'Neuer Nutzer',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/office/users/new'),
          ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Keine Nutzer gefunden.'),
            ),
          for (final u in _users)
            Card(
              child: ListTile(
                leading: Icon(u.disabled ? Icons.block_rounded : Icons.person_rounded),
                title: Text('${u.displayName} (${u.username})'),
                subtitle: Text(
                  'Roles: ${u.roles.join(', ')}${u.disabled ? '\nDeaktiviert' : ''}',
                ),
                isThreeLine: u.disabled,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/office/users/${u.id}/edit'),
              ),
            ),
        ],
      ),
    );
  }
}
