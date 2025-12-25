import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class MyFinesPage extends StatefulWidget {
  final ApiClient api;

  const MyFinesPage({super.key, required this.api});

  @override
  State<MyFinesPage> createState() => _MyFinesPageState();
}

class _MyFinesPageState extends State<MyFinesPage> {
  bool _loading = true;

  String? _myUserId;
  ConventPeriodDto? _activePeriod;

  List<FineDto> _mine = const [];
  Map<String, ConventPeriodDto> _periodById = const {};
  Map<String, UserPickerDto> _userById = const {};

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

  String _userLabel(String id) {
    final u = _userById[id];
    if (u == null) return id;
    return u.displayName;
  }

  String _fineTitle(FineDto f) {
    return 'Beihängung';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final period = await widget.api.getActivePeriod();
      final bal = await widget.api.getMyBalance(periodId: period.id);
      final fines = await widget.api.listFines();
      final periods = await widget.api.listPeriods();
      final users = await widget.api.pickerUsers();

      final periodById = {for (final p in periods) p.id: p};
      final userById = {for (final u in users) u.id: u};

      // Backend may already filter for MEMBER, but we keep safe filter.
      final mine = fines.where((f) => f.targetUserIds.contains(bal.userId)).toList();

      if (!mounted) return;
      setState(() {
        _activePeriod = period;
        _myUserId = bal.userId;
        _mine = mine;
        _periodById = periodById;
        _userById = userById;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beihängungen laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _buildGrouped();

    return AppScaffold(
      title: 'Meine Beihängungen',
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
            if (_activePeriod != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  'Aktive Periode: ${_activePeriod!.semester}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_myUserId == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Fehler: userId unbekannt.'),
              ),
            if (grouped.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Keine Beihängungen gefunden.'),
              ),
            for (final sem in grouped)
              _SemesterSection(
                semester: sem.semester,
                periods: sem.periods,
                periodById: _periodById,
                fineTitle: _fineTitle,
                userLabel: _userLabel,
                myUserId: _myUserId!,
                onTapFine: (id) => context.push('/fines/$id'),
              ),
          ],
        ),
      ),
    );
  }

  List<_SemesterGroup> _buildGrouped() {
    if (_myUserId == null) return [];

    final Map<String, Map<String, List<FineDto>>> map = {};

    for (final f in _mine) {
      final p = _periodById[f.periodId];
      final semester = p?.semester ?? 'Unbekannt';
      map.putIfAbsent(semester, () => {});
      map[semester]!.putIfAbsent(f.periodId, () => []);
      map[semester]![f.periodId]!.add(f);
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
          final pa = _periodById[a];
          final pb = _periodById[b];
          final da = pa == null ? DateTime.fromMillisecondsSinceEpoch(0) : Format.parseIsoToLocal(pa.startAt);
          final db = pb == null ? DateTime.fromMillisecondsSinceEpoch(0) : Format.parseIsoToLocal(pb.startAt);
          return db.compareTo(da);
        });

      final periods = <_PeriodGroup>[];
      for (final pid in periodIds) {
        final fines = [...periodMap[pid]!]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        periods.add(_PeriodGroup(periodId: pid, fines: fines));
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
  final String periodId;
  final List<FineDto> fines;

  _PeriodGroup({required this.periodId, required this.fines});
}

class _SemesterSection extends StatelessWidget {
  final String semester;
  final List<_PeriodGroup> periods;
  final Map<String, ConventPeriodDto> periodById;

  final String Function(FineDto) fineTitle;
  final String Function(String userId) userLabel;
  final String myUserId;
  final void Function(String fineId) onTapFine;

  const _SemesterSection({
    required this.semester,
    required this.periods,
    required this.periodById,
    required this.fineTitle,
    required this.userLabel,
    required this.myUserId,
    required this.onTapFine,
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
                fineTitle: fineTitle,
                userLabel: userLabel,
                myUserId: myUserId,
                onTapFine: onTapFine,
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

  final String Function(FineDto) fineTitle;
  final String Function(String userId) userLabel;
  final String myUserId;
  final void Function(String fineId) onTapFine;

  const _PeriodSection({
    required this.pg,
    required this.period,
    required this.fineTitle,
    required this.userLabel,
    required this.myUserId,
    required this.onTapFine,
  });

  @override
  Widget build(BuildContext context) {
    final p = period;
    final header = (p == null)
        ? 'Periode: ${pg.periodId}'
        : 'Periode: ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}';

    final sumCents = pg.fines.fold<int>(0, (acc, f) {
      final amount = f.amountCents ?? 0;
      // member cost counts if the member is targeted
      return acc + (f.targetUserIds.contains(myUserId) ? amount : 0);
    });

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
          const SizedBox(height: 4),
          Text('Summe: ${Format.centsToEur(sumCents)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final f in pg.fines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: const Icon(Icons.gavel_rounded),
                  title: Text(fineTitle(f)),
                  subtitle: Text(_subtitleForFine(f)),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onTapFine(f.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _subtitleForFine(FineDto f) {
    final amount = f.amountCents ?? 0;

    // show creator resolved if possible
    final creator = userLabel(f.creatorUserId);

    return 'Betrag: ${Format.centsToEur(amount)} · Creator: $creator\n'
        'Datum: ${Format.dateTimeShort(f.createdAt)}';
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
