import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class EventsPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const EventsPage({super.key, required this.api, required this.authStore});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  bool _loading = true;

  List<EventDto> _events = const [];
  Map<String, ConventPeriodDto> _periodById = const {};
  List<ConventPeriodDto> _periodsSorted = const [];
  Map<String, UserPickerDto> _userById = const {};

  bool _showPast = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static ({int year, int term}) _semesterKey(String semester) {
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

  String _userName(String id) {
    final u = _userById[id];
    if (u == null) return id;
    return u.displayName;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final periods = await widget.api.listPeriods();
      final events = await widget.api.listEvents();
      final users = await widget.api.pickerUsers();

      // sort periods by startAt ascending for deterministic range matching
      periods.sort((a, b) => a.startAt.compareTo(b.startAt));

      final periodById = {for (final p in periods) p.id: p};
      final userById = {for (final u in users) u.id: u};

      if (!mounted) return;
      setState(() {
        _periodById = periodById;
        _periodsSorted = periods;
        _userById = userById;
        _events = events;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Termine laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _canEditEvent(Set<AppRole> roles, EventDto e) {
    if (Roles.canManageAnyEvent(roles)) return true;
    if (Roles.isHousekeeping(roles) && e.ownerType == EventOwnerType.housekeeping) {
      return false;
    }
    return false;
  }

  ConventPeriodDto? _periodForEvent(EventDto e) {
    // event time is ISO UTC; compare in local time consistently
    final dt = Format.parseIsoToLocal(e.startsAt);

    for (final p in _periodsSorted) {
      final start = Format.parseIsoToLocal(p.startAt);
      final end = Format.parseIsoToLocal(p.endAt);

      // inclusive start + inclusive end
      if (!dt.isBefore(start) && !dt.isAfter(end)) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final canCreate = Roles.canCreateEvent(roles);

    final grouped = _buildGrouped(_events);

    return AppScaffold(
      title: 'Termine / Kalender',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        IconButton(
          tooltip: _showPast ? 'Vergangenheit ausblenden' : 'Vergangenheit anzeigen',
          icon: Icon(_showPast ? Icons.history_toggle_off_rounded : Icons.history_rounded),
          onPressed: _loading
              ? null
              : () => setState(() {
            _showPast = !_showPast;
          }),
        ),
        if (canCreate)
          IconButton(
            tooltip: 'Neuer Termin',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => GoRouter.of(context).push('/events/new'),
          ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (grouped.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Keine Termine gefunden.'),
              ),
            for (final sem in grouped)
              _SemesterSection(
                semester: sem.semester,
                periods: sem.periods,
                periodById: _periodById,
                userName: _userName,
                showPast: _showPast,
                canEdit: (e) => _canEditEvent(roles, e),
                onEdit: (id) => GoRouter.of(context).push('/events/$id/edit'),
              ),
          ],
        ),
      ),
    );
  }

  List<_SemesterGroup> _buildGrouped(List<EventDto> all) {
    // Group: Semester -> Period -> events
    final Map<String, Map<String, List<EventDto>>> map = {};

    for (final e in all) {
      final p = _periodForEvent(e);
      final semester = p?.semester ?? 'Unbekannt';

      // if unknown, group by a stable pseudo id to avoid mixing with real ids
      final pid = p?.id ?? 'unknown';

      map.putIfAbsent(semester, () => {});
      map[semester]!.putIfAbsent(pid, () => []);
      map[semester]![pid]!.add(e);
    }

    final semesters = map.keys.toList()
      ..sort((a, b) {
        final ka = _semesterKey(a);
        final kb = _semesterKey(b);
        final c1 = kb.year.compareTo(ka.year);
        if (c1 != 0) return c1;
        return kb.term.compareTo(ka.term);
      });

    final result = <_SemesterGroup>[];
    for (final sem in semesters) {
      final periodMap = map[sem]!;
      final periodIds = periodMap.keys.toList()
        ..sort((a, b) {
          // unknown goes last
          if (a == 'unknown' && b != 'unknown') return 1;
          if (b == 'unknown' && a != 'unknown') return -1;

          final pa = _periodById[a];
          final pb = _periodById[b];
          final da = pa == null ? DateTime.fromMillisecondsSinceEpoch(0) : Format.parseIsoToLocal(pa.startAt);
          final db = pb == null ? DateTime.fromMillisecondsSinceEpoch(0) : Format.parseIsoToLocal(pb.startAt);
          return db.compareTo(da); // newest period first within semester
        });

      final periods = <_PeriodGroup>[];
      for (final pid in periodIds) {
        final events = [...periodMap[pid]!]
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt)); // chronological in a period
        periods.add(_PeriodGroup(periodId: pid, events: events));
      }

      result.add(_SemesterGroup(semester: sem, periods: periods));
    }

    return result;
  }
}

class _SemesterGroup {
  final String semester;
  final List<_PeriodGroup> periods;

  _SemesterGroup({required this.semester, required this.periods});
}

class _PeriodGroup {
  final String periodId; // real id or 'unknown'
  final List<EventDto> events;

  _PeriodGroup({required this.periodId, required this.events});
}

class _SemesterSection extends StatelessWidget {
  final String semester;
  final List<_PeriodGroup> periods;
  final Map<String, ConventPeriodDto> periodById;

  final String Function(String userId) userName;
  final bool showPast;
  final bool Function(EventDto e) canEdit;
  final void Function(String eventId) onEdit;

  const _SemesterSection({
    required this.semester,
    required this.periods,
    required this.periodById,
    required this.userName,
    required this.showPast,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(semester, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final pg in periods)
              _PeriodSection(
                pg: pg,
                period: periodById[pg.periodId],
                userName: userName,
                showPast: showPast,
                canEdit: canEdit,
                onEdit: onEdit,
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSection extends StatelessWidget {
  final _PeriodGroup pg;
  final ConventPeriodDto? period;

  final String Function(String userId) userName;
  final bool showPast;
  final bool Function(EventDto e) canEdit;
  final void Function(String eventId) onEdit;

  const _PeriodSection({
    required this.pg,
    required this.period,
    required this.userName,
    required this.showPast,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = period;

    final header = (p == null)
        ? (pg.periodId == 'unknown' ? 'Periode: Unbekannt' : 'Periode: ${pg.periodId}')
        : 'Periode: ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}';

    final now = DateTime.now();
    final visibleEvents = pg.events.where((e) {
      if (showPast) return true;
      final dt = Format.parseIsoToLocal(e.startsAt);
      return !dt.isBefore(now);
    }).toList();

    if (visibleEvents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(header, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text('Keine zukünftigen Termine.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    final flags = <Widget>[];
    if (p?.active == true) flags.add(_Chip(text: 'Aktiv', icon: Icons.play_arrow_rounded));
    if (p?.locked == true) flags.add(_Chip(text: 'Locked', icon: Icons.lock_rounded));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(header, style: Theme.of(context).textTheme.titleSmall)),
              ...flags,
            ],
          ),
          const SizedBox(height: 6),
          for (final e in visibleEvents)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: Icon(e.mandatory ? Icons.star_rounded : Icons.event_rounded),
                  title: Text(e.title),
                  subtitle: Text(
                    '${Format.dateShort(e.startsAt)} · ${Format.timeShort(e.startsAt)}\n'
                        'Creator: ${userName(e.creatorUserId)}',
                  ),
                  isThreeLine: true,
                  trailing: canEdit(e) ? const Icon(Icons.edit_rounded) : null,
                  onTap: canEdit(e) ? () => onEdit(e.id) : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Chip({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
