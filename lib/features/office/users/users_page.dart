import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';
import '../../../models/member_status.dart';

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
  _OnlineFilter _onlineFilter = _OnlineFilter.all;

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
      case 'FECHTWART':
        return 'Fechtwart';
      case 'MEMBER':
        return 'Mitglied';
      case 'ADMIN':
        return 'Admin';
      case 'TREASURER':
        return 'Kassenwart';
      default:
        return role;
    }
  }

  String? get _backendOnlineFilter {
    switch (_onlineFilter) {
      case _OnlineFilter.all:
        return null;
      case _OnlineFilter.week:
        return 'week';
      case _OnlineFilter.month:
        return 'month';
      case _OnlineFilter.today:
      case _OnlineFilter.year:
      case _OnlineFilter.never:
        return null;
    }
  }

  bool get _showLastOnline => _onlineFilter != _OnlineFilter.all;

  Future<void> _openCreateUser() async {
    final changed = await context.push<bool>('/office/users/new');
    if (changed == true && mounted) {
      await _load(force: true);
    }
  }

  Future<void> _openEditUser(UserDto u) async {
    final changed = await context.push<bool>('/office/users/${u.id}/edit');
    if (changed == true && mounted) {
      await _load(force: true);
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);

    try {
      final roles = widget.authStore.currentRoles;
      if (!Roles.canManageUsers(roles)) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Keine Berechtigung.')));
        return;
      }

      final users = await widget.api.listUsersAdmin(
        online: _backendOnlineFilter,
      );
      final filtered = _applyClientOnlineFilter(users);

      filtered.sort((a, b) {
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
      setState(() => _users = filtered);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nutzer laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<UserDto> _applyClientOnlineFilter(List<UserDto> users) {
    switch (_onlineFilter) {
      case _OnlineFilter.all:
      case _OnlineFilter.week:
      case _OnlineFilter.month:
        return users;

      case _OnlineFilter.today:
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final end = start.add(const Duration(days: 1));

        return users
            .where((u) {
              final dt = _parseDate(u.lastOnlineAt);
              if (dt == null) return false;

              return !dt.isBefore(start) && dt.isBefore(end);
            })
            .toList(growable: false);

      case _OnlineFilter.year:
        final now = DateTime.now();
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year + 1, 1, 1);

        return users
            .where((u) {
              final dt = _parseDate(u.lastOnlineAt);
              if (dt == null) return false;

              return !dt.isBefore(start) && dt.isBefore(end);
            })
            .toList(growable: false);

      case _OnlineFilter.never:
        return users
            .where((u) {
              final raw = u.lastOnlineAt;
              return raw == null || raw.trim().isEmpty;
            })
            .toList(growable: false);
    }
  }

  DateTime? _parseDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }

  String _roleLabel(UserDto u) {
    if (u.roles.isEmpty) return '—';
    return u.roles.map(_roleLabelUi).join(', ');
  }

  String _date(String? iso) {
    if (iso == null || iso.trim().isEmpty) return 'nie online';

    try {
      return Format.dateTimeShort(iso);
    } catch (_) {
      return iso;
    }
  }

  Future<void> _openSearch() async {
    final controller = TextEditingController(text: _searchQuery);

    final result = await showSearch<String?>(
      context: context,
      delegate: _UsersSearchDelegate(users: _users, initialQuery: _searchQuery),
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
      final status = MemberStatuses.label(u.memberStatus).toLowerCase();

      return username.contains(q) ||
          displayName.contains(q) ||
          status.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final roles = widget.authStore.currentRoles;
    final canCreate = Roles.canManageUsers(roles);
    final filteredUsers = _filteredUsers;

    return AppScaffold(
      title: 'Nutzer',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Suchen',
          icon: const Icon(Icons.search_rounded),
          onPressed: _loading ? null : _openSearch,
        ),
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
        if (canCreate)
          IconButton(
            tooltip: 'Neuer Nutzer',
            icon: const Icon(Icons.add_rounded),
            onPressed: _openCreateUser,
          ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _UsersFilterBar(
                  value: _onlineFilter,
                  count: filteredUsers.length,
                  onChanged: (value) {
                    setState(() => _onlineFilter = value);
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                if (filteredUsers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Keine Nutzer gefunden.'),
                  ),
                for (final u in filteredUsers)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        u.disabled ? Icons.block_rounded : Icons.person_rounded,
                      ),
                      titleAlignment: ListTileTitleAlignment.center,
                      title: Text('${u.displayName} (${u.username})'),
                      subtitle: Text(
                        _showLastOnline
                            ? 'Rollen: ${_roleLabel(u)}'
                                  '\nStatus: ${MemberStatuses.label(u.memberStatus)}'
                                  '\nZuletzt online: ${_date(u.lastOnlineAt)}'
                                  '${u.disabled ? '\nDeaktiviert' : ''}'
                            : 'Rollen: ${_roleLabel(u)}'
                                  '\nStatus: ${MemberStatuses.label(u.memberStatus)}'
                                  '${u.disabled ? '\nDeaktiviert' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openEditUser(u),
                    ),
                  ),
              ],
            ),
    );
  }
}

enum _OnlineFilter { all, today, week, month, year, never }

extension _OnlineFilterUi on _OnlineFilter {
  String get label {
    switch (this) {
      case _OnlineFilter.all:
        return 'Alle';
      case _OnlineFilter.today:
        return 'Online heute';
      case _OnlineFilter.week:
        return 'Online diese Woche';
      case _OnlineFilter.month:
        return 'Online diesen Monat';
      case _OnlineFilter.year:
        return 'Online dieses Jahr';
      case _OnlineFilter.never:
        return 'Nie online';
    }
  }
}

class _UsersFilterBar extends StatelessWidget {
  final _OnlineFilter value;
  final int count;
  final ValueChanged<_OnlineFilter> onChanged;

  const _UsersFilterBar({
    required this.value,
    required this.count,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_OnlineFilter>(
                  value: value,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(12),
                  icon: const Icon(Icons.expand_more_rounded),
                  style: theme.textTheme.titleSmall,
                  items: [
                    for (final item in _OnlineFilter.values)
                      DropdownMenuItem(
                        value: item,
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (newValue) {
                    if (newValue == null || newValue == value) return;
                    onChanged(newValue);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$count', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _UsersSearchDelegate extends SearchDelegate<String?> {
  final List<UserDto> users;

  _UsersSearchDelegate({required this.users, String initialQuery = ''}) {
    query = initialQuery;
  }

  List<UserDto> _filterUsers(String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return users;

    return users.where((u) {
      final username = u.username.toLowerCase();
      final displayName = u.displayName.toLowerCase();
      final status = MemberStatuses.label(u.memberStatus).toLowerCase();

      return username.contains(needle) ||
          displayName.contains(needle) ||
          status.contains(needle);
    }).toList();
  }

  @override
  String get searchFieldLabel =>
      'Nach Username, Anzeigename oder Status suchen';

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
              leading: Icon(
                u.disabled ? Icons.block_rounded : Icons.person_rounded,
              ),
              titleAlignment: ListTileTitleAlignment.center,
              title: Text('${u.displayName} (${u.username})'),
              subtitle: Text(
                'Status: ${MemberStatuses.label(u.memberStatus)}'
                '${u.disabled ? '\nDeaktiviert' : ''}',
              ),
              isThreeLine: u.disabled,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => close(context, query),
            ),
          ),
      ],
    );
  }
}
