import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';
import '../../../models/member_status.dart';

class ActiveMemberStatsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const ActiveMemberStatsPage({
    super.key,
    required this.api,
    required this.authStore,
  });

  @override
  State<ActiveMemberStatsPage> createState() => _ActiveMemberStatsPageState();
}

class _ActiveMemberStatsPageState extends State<ActiveMemberStatsPage> {
  bool _loading = true;
  List<UserDto> _activeMembers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final roles = widget.authStore.currentRoles;
      final allowed =
          roles.contains(AppRole.admin) ||
              roles.contains(AppRole.senior) ||
              roles.contains(AppRole.housekeeping) ||
              roles.contains(AppRole.treasurer);

      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Berechtigung.')),
        );
        setState(() => _activeMembers = const []);
        return;
      }

      final users = await widget.api.listUsersAdmin();

      final activeMembers = users.where((u) {
        return !u.disabled && u.aktivitas;
      }).toList(growable: false);

      activeMembers.sort((a, b) {
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
      setState(() => _activeMembers = activeMembers);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aktivenstände laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<UserDto> _usersByStatus(MemberStatus status) {
    return _activeMembers.where((u) {
      return MemberStatuses.parse(u.memberStatus) == status;
    }).toList(growable: false);
  }

  Widget _sectionWithSpacing({
    required String title,
    required IconData icon,
    required List<UserDto> users,
  }) {
    if (users.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _StatusSection(
        title: title,
        icon: icon,
        users: users,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fuxUsers = _usersByStatus(MemberStatus.fux);
    final schuelerfuxUsers = _usersByStatus(MemberStatus.schuelerfux);
    final konkneipantUsers = _usersByStatus(MemberStatus.konkneipant);
    final burschUsers = _usersByStatus(MemberStatus.bursch);
    final inaktiverUsers = _usersByStatus(MemberStatus.inaktiver);
    final total = _activeMembers.length;

    return AppScaffold(
      title: 'Aktivenstände',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _SummaryCard(total: total),
            _sectionWithSpacing(
              title: 'Füxe',
              icon: Icons.school_rounded,
              users: fuxUsers,
            ),
            _sectionWithSpacing(
              title: 'Schüler-/Militärfüxe',
              icon: Icons.military_tech,
              users: schuelerfuxUsers,
            ),
            _sectionWithSpacing(
              title: 'Konkneipanten',
              icon: Icons.person_add_alt_1_rounded,
              users: konkneipantUsers,
            ),
            _sectionWithSpacing(
              title: 'Aktive Burschen',
              icon: Icons.groups_rounded,
              users: burschUsers,
            ),
            _sectionWithSpacing(
              title: 'Inaktive Burschen',
              icon: Icons.person_off_rounded,
              users: inaktiverUsers,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int total;

  const _SummaryCard({
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.groups_rounded,
              color: cs.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Aktivitas gesamt',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              '$total',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<UserDto> users;

  const _StatusSection({
    required this.title,
    required this.icon,
    required this.users,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('${users.length} Nutzer'),
        children: [
          ...users.map(
                (u) => ListTile(
              dense: true,
              titleAlignment: ListTileTitleAlignment.center,
              title: Text(
                u.displayName.trim().isEmpty
                    ? 'Ohne Anzeigename'
                    : u.displayName,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}