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
  List<UserDto> _users = const [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _roleLabelUi(String role) {
    switch (role.toUpperCase()) {
      case 'SENIOR':
        return 'Sprecher';
      case 'HOUSEKEEPING':
        return 'Schmuckwart';
      case 'MEMBER':
        return 'Mitglied';
      case 'ADMIN':
        return 'Admin';
      case 'TREASURER':
        return 'Kassenwart';
      default:
        return role; // ADMIN, TREASURER, unbekannt
    }
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

      // Correct admin endpoint: GET /users (no query params)
      final users = await widget.api.listUsersAdmin();

      users.sort((a, b) {
        final ad = a.displayName.trim().toLowerCase();
        final bd = b.displayName.trim().toLowerCase();
        if (ad.isEmpty && bd.isEmpty) {
          return a.username.toLowerCase().compareTo(b.username.toLowerCase());
        }
        if (ad.isEmpty) return 1;
        if (bd.isEmpty) return -1;
        return ad.compareTo(bd);
      });

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

  String _singleRoleLabel(UserDto u) {
    if (u.roles.isEmpty) return '—';
    return _roleLabelUi(u.roles.first);
  }

  Future<void> _openSearch() async {
    final controller = TextEditingController(text: _searchQuery);

    final result = await showSearch<String?>(
      context: context,
      delegate: _UsersSearchDelegate(
        users: _users,
        initialQuery: _searchQuery,
      ),
    );

    controller.dispose();

    if (result != null && mounted) {
      setState(() => _searchQuery = result);
    }
  }

  List<UserDto> get _filteredUsers {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _users;

    return _users.where((u) {
      final username = u.username.toLowerCase();
      final displayName = u.displayName.toLowerCase();
      return username.contains(q) || displayName.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final canCreate = Roles.canManageUsers(roles);
    final filteredUsers = _filteredUsers;

    return AppScaffold(
      title: 'Nutzer',
      actions: [
        IconButton(
          tooltip: 'Suchen',
          icon: const Icon(Icons.search_rounded),
          onPressed: _loading ? null : _openSearch,
        ),
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
          if (filteredUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Keine Nutzer gefunden.'),
            ),
          for (final u in filteredUsers)
            Card(
              child: ListTile(
                leading: Icon(u.disabled ? Icons.block_rounded : Icons.person_rounded),
                title: Text('${u.displayName} (${u.username})'),
                subtitle: Text(
                  'Role: ${_singleRoleLabel(u)}${u.disabled ? '\nDeaktiviert' : ''}',
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

class _UsersSearchDelegate extends SearchDelegate<String?> {
  final List<UserDto> users;

  _UsersSearchDelegate({
    required this.users,
    String initialQuery = '',
  }) {
    query = initialQuery;
  }

  List<UserDto> _filterUsers(String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return users;

    return users.where((u) {
      final username = u.username.toLowerCase();
      final displayName = u.displayName.toLowerCase();
      return username.contains(needle) || displayName.contains(needle);
    }).toList();
  }

  @override
  String get searchFieldLabel => 'Nach Username oder Anzeigename suchen';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Leeren',
          icon: const Icon(Icons.clear_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Zurück',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    close(context, query);
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final filteredUsers = _filterUsers(query);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (filteredUsers.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Keine Nutzer gefunden.'),
          ),
        for (final u in filteredUsers)
          Card(
            child: ListTile(
              leading: Icon(u.disabled ? Icons.block_rounded : Icons.person_rounded),
              title: Text('${u.displayName} (${u.username})'),
              subtitle: Text(
                u.disabled ? 'Deaktiviert' : '',
              ),
              isThreeLine: false,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => close(context, query),
            ),
          ),
      ],
    );
  }
}