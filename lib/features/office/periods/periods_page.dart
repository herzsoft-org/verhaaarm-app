import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class PeriodsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const PeriodsPage({super.key, required this.api, required this.authStore});

  @override
  State<PeriodsPage> createState() => _PeriodsPageState();
}

class _PeriodsPageState extends State<PeriodsPage> {
  bool _loading = true;
  List<ConventPeriodDto> _periods = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static ({int year, int term}) _semesterKey(String semester) {
    // SS25 => year=2025 term=1
    // WS25/26 => year=2025 term=2
    final s = semester.trim().toUpperCase();
    if (s.startsWith('SS')) {
      final yy = int.tryParse(s.substring(2).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return (year: 2000 + yy, term: 1);
    }
    if (s.startsWith('WS')) {
      final m = RegExp(r'^WS(\d{2})').firstMatch(s);
      final yy = (m == null) ? 0 : int.tryParse(m.group(1)!) ?? 0;
      return (year: 2000 + yy, term: 2);
    }
    return (year: 0, term: 0);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!Roles.canManagePeriods(roles)) {
        if (!mounted) return;
        context.go('/home');
        return;
      }

      final periods = await widget.api.listPeriods();

      if (!mounted) return;
      setState(() => _periods = periods);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Laden fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate(String id) async {
    try {
      await widget.api.activatePeriod(id);
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Periode aktiviert.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aktivieren fehlgeschlagen: $e')));
    }
  }

  Future<void> _lock(String id) async {
    try {
      await widget.api.lockPeriod(id);
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Periode gelockt.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lock fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<ConventPeriodDto>> bySemester = {};
    for (final p in _periods) {
      bySemester.putIfAbsent(p.semester, () => <ConventPeriodDto>[]);
      bySemester[p.semester]!.add(p);
    }

    final semesters = bySemester.keys.toList()
      ..sort((a, b) {
        final ka = _semesterKey(a);
        final kb = _semesterKey(b);
        final c1 = kb.year.compareTo(ka.year);
        if (c1 != 0) return c1;
        return kb.term.compareTo(ka.term);
      });

    return AppScaffold(
      title: 'Semester / Perioden',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        IconButton(
          tooltip: 'Neu',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => context.push('/office/periods/new'),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (semesters.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Keine Perioden gefunden.'),
            ),
          for (final sem in semesters) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(sem, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final p in (bySemester[sem]!..sort((a, b) => b.startAt.compareTo(a.startAt))))
              Card(
                child: ListTile(
                  titleAlignment: ListTileTitleAlignment.center,
                  title: Text('${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}'),
                  subtitle: Text(
                    [
                      if (p.active) 'Aktiv',
                      if (p.locked) 'Locked',
                    ].join(' · ').isEmpty
                        ? '—'
                        : [
                      if (p.active) 'Aktiv',
                      if (p.locked) 'Locked',
                    ].join(' · '),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'edit':
                          context.push('/office/periods/${p.id}/edit');
                          break;
                        case 'activate':
                          await _activate(p.id);
                          break;
                        case 'lock':
                          await _lock(p.id);
                          break;
                        case 'delete':
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Löschen braucht Backend-Endpoint (DELETE /periods/{id}).'),
                            ),
                          );
                          break;
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                      PopupMenuItem(value: 'activate', child: Text('Aktivieren (setzt andere inaktiv)')),
                      PopupMenuItem(value: 'lock', child: Text('Lock')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'delete', child: Text('Löschen (noch nicht)')),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
