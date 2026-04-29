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
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
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

  int _countByStatus(MemberStatus status) {
    return _activeMembers.where((u) {
      return MemberStatuses.parse(u.memberStatus) == status;
    }).length;
  }

  List<UserDto> _usersByStatus(MemberStatus status) {
    return _activeMembers.where((u) {
      return MemberStatuses.parse(u.memberStatus) == status;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final fuxCount = _countByStatus(MemberStatus.fux);
    final burschCount = _countByStatus(MemberStatus.bursch);
    final inaktiverCount = _countByStatus(MemberStatus.inaktiver);
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
            _SummaryCard(
              total: total,
              fuxCount: fuxCount,
              burschCount: burschCount,
              inaktiverCount: inaktiverCount,
            ),
            const SizedBox(height: 12),
            _StatusSection(
              title: 'Füxe',
              icon: Icons.school_rounded,
              users: _usersByStatus(MemberStatus.fux),
            ),
            const SizedBox(height: 12),
            _StatusSection(
              title: 'Aktive Burschen',
              icon: Icons.groups_rounded,
              users: _usersByStatus(MemberStatus.bursch),
            ),
            const SizedBox(height: 12),
            _StatusSection(
              title: 'Inaktive Burschen',
              icon: Icons.person_off_rounded,
              users: _usersByStatus(MemberStatus.inaktiver),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int total;
  final int fuxCount;
  final int burschCount;
  final int inaktiverCount;

  const _SummaryCard({
    required this.total,
    required this.fuxCount,
    required this.burschCount,
    required this.inaktiverCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aktivitas gesamt', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '$total',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountChip(label: 'Füxe', count: fuxCount),
                _CountChip(label: 'Aktive Burschen', count: burschCount),
                _CountChip(label: 'Inaktive Burschen', count: inaktiverCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;

  const _CountChip({
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $count'),
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
        initiallyExpanded: true,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text('${users.length} Nutzer'),
        children: [
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Keine Nutzer.'),
              ),
            )
          else
            ...users.map(
                  (u) => ListTile(
                    dense: true,
                    title: Text(
                      u.displayName.trim().isEmpty ? 'Ohne Anzeigename' : u.displayName,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
            )
        ],
      ),
    );
  }
}