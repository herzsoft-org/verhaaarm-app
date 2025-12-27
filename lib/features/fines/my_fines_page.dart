import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/cache/app_cache.dart';
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
  static const _ttlMyFines = Duration(minutes: 3);

  static const _kMyFinesActivePeriod = 'myfines.activePeriod';
  static const _kMyFinesBalance = 'myfines.balance';
  static const _kMyFinesFines = 'myfines.fines';
  static const _kMyFinesPeriods = 'myfines.periods';
  static const _kMyFinesUsers = 'myfines.users';

  bool _loading = true;
  bool _refreshing = false;

  String? _myUserId;
  ConventPeriodDto? _activePeriod;

  List<FineDto> _mine = const [];
  List<ConventPeriodDto> _periods = const [];
  Map<String, ConventPeriodDto> _periodById = const {};
  Map<String, UserPickerDto> _userById = const {};

  Map<String, dynamic> _encodePeriod(ConventPeriodDto p) => {
    'id': p.id,
    'semester': p.semester,
    'startAt': p.startAt,
    'endAt': p.endAt,
    'active': p.active,
    'locked': p.locked,
  };

  ConventPeriodDto _decodePeriod(Object json) =>
      ConventPeriodDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeBalance(UserBalanceDto b) => {
    'userId': b.userId,
    'balanceCents': b.balanceCents,
  };

  UserBalanceDto _decodeBalance(Object json) =>
      UserBalanceDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeUser(UserPickerDto u) => {
    'id': u.id,
    'displayName': u.displayName,
  };

  UserPickerDto _decodeUser(Object json) =>
      UserPickerDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeFine(FineDto f) => {
    'id': f.id,
    'creatorUserId': f.creatorUserId,
    'targetUserIds': f.targetUserIds,
    'amountCents': f.amountCents,
    'reason': f.reason,
    'catalogItemId': f.catalogItemId,
    'fineDate': f.fineDate,
    'createdAt': f.createdAt,
  };

  FineDto _decodeFine(Object json) => FineDto.fromJson((json as Map).cast<String, dynamic>());

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
      final yy = int.tryParse(m?.group(1) ?? '') ?? 0;
      return (year: 2000 + yy, term: 2);
    }
    return (year: 0, term: 0);
  }

  String _userLabel(String id) => _userById[id]?.displayName ?? id;

  String _fineTitle(FineDto f) => 'Beihängung';

  Future<void> _load({bool force = false}) async {
    try {
      final cPeriod = await AppCache.I.entryOrLoadPersisted<ConventPeriodDto>(
        _kMyFinesActivePeriod,
        decode: _decodePeriod,
      );
      final cBal = await AppCache.I.entryOrLoadPersisted<UserBalanceDto>(
        _kMyFinesBalance,
        decode: _decodeBalance,
      );
      final cFines = await AppCache.I.entryOrLoadPersisted<List<FineDto>>(
        _kMyFinesFines,
        decode: (json) => (json as List).map((e) => _decodeFine(e as Object)).toList(growable: false),
      );
      final cPeriods = await AppCache.I.entryOrLoadPersisted<List<ConventPeriodDto>>(
        _kMyFinesPeriods,
        decode: (json) =>
            (json as List).map((e) => _decodePeriod(e as Object)).toList(growable: false),
      );
      final cUsers = await AppCache.I.entryOrLoadPersisted<List<UserPickerDto>>(
        _kMyFinesUsers,
        decode: (json) => (json as List).map((e) => _decodeUser(e as Object)).toList(growable: false),
      );

      final hasAnyCache =
          (cPeriod != null) || (cBal != null) || (cFines != null) || (cPeriods != null) || (cUsers != null);

      if (hasAnyCache && mounted) {
        final periods = List<ConventPeriodDto>.from(cPeriods?.value ?? const <ConventPeriodDto>[]);
        final users = List<UserPickerDto>.from(cUsers?.value ?? const <UserPickerDto>[]);

        final periodById = {for (final p in periods) p.id: p};
        final userById = {for (final u in users) u.id: u};

        final myUserId = cBal?.value.userId;
        final mine = (myUserId == null)
            ? const <FineDto>[]
            : (cFines?.value ?? const <FineDto>[]).where((f) => f.targetUserIds.contains(myUserId)).toList();

        setState(() {
          _activePeriod = cPeriod?.value;
          _myUserId = myUserId;
          _mine = mine;
          _periods = periods;
          _periodById = periodById;
          _userById = userById;
          _loading = false;
        });
      }

      final cacheFresh = (cPeriod != null && cPeriod.isFresh(_ttlMyFines)) &&
          (cBal != null && cBal.isFresh(_ttlMyFines)) &&
          (cFines != null && cFines.isFresh(_ttlMyFines)) &&
          (cPeriods != null && cPeriods.isFresh(_ttlMyFines)) &&
          (cUsers != null && cUsers.isFresh(_ttlMyFines));

      if (!force && cacheFresh) return;

      final showFullSpinner = !hasAnyCache;
      if (mounted) {
        setState(() {
          _loading = showFullSpinner;
          _refreshing = !showFullSpinner;
        });
      }

      try {
        final period = await widget.api.getActivePeriod();
        final bal = await widget.api.getMyBalance(periodId: period.id);
        final fines = await widget.api.listFines();
        final periods = await widget.api.listPeriods();
        final users = await widget.api.pickerUsers();

        await AppCache.I.setPersisted<ConventPeriodDto>(
          _kMyFinesActivePeriod,
          period,
          encode: _encodePeriod,
        );
        await AppCache.I.setPersisted<UserBalanceDto>(
          _kMyFinesBalance,
          bal,
          encode: _encodeBalance,
        );
        await AppCache.I.setPersisted<List<FineDto>>(
          _kMyFinesFines,
          List<FineDto>.unmodifiable(fines),
          encode: (v) => v.map(_encodeFine).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<ConventPeriodDto>>(
          _kMyFinesPeriods,
          List<ConventPeriodDto>.unmodifiable(periods),
          encode: (v) => v.map(_encodePeriod).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<UserPickerDto>>(
          _kMyFinesUsers,
          List<UserPickerDto>.unmodifiable(users),
          encode: (v) => v.map(_encodeUser).toList(growable: false),
        );

        final periodById = {for (final p in periods) p.id: p};
        final userById = {for (final u in users) u.id: u};

        final mine = fines.where((f) => f.targetUserIds.contains(bal.userId)).toList();

        if (!mounted) return;
        setState(() {
          _activePeriod = period;
          _myUserId = bal.userId;
          _mine = mine;
          _periods = periods;
          _periodById = periodById;
          _userById = userById;
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Beihängungen laden fehlgeschlagen: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
            _refreshing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _myUserId;
    final grouped = _buildGrouped();

    return AppScaffold(
      title: 'Meine Beihängungen',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (_activePeriod != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  'Aktive Conventsperiode: ${_activePeriod!.semester}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (myId == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Fehler: userId unbekannt.'),
              ),
            if (grouped.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Keine Beihängungen gefunden.'),
              ),
            if (myId != null)
              for (final sem in grouped)
                _SemesterSection(
                  semester: sem.semester,
                  periods: sem.periods,
                  periodById: _periodById,
                  fineTitle: _fineTitle,
                  userLabel: _userLabel,
                  myUserId: myId,
                  onTapFine: (id) => context.push('/fines/$id'),
                ),
          ],
        ),
      ),
    );
  }

  List<_SemesterGroup> _buildGrouped() {
    final myId = _myUserId;
    if (myId == null) return const [];

    final periodsSorted = [..._periods]
      ..sort((a, b) => Format.parseIsoToLocal(b.startAt).compareTo(Format.parseIsoToLocal(a.startAt)));

    final Map<String, Map<String, List<FineDto>>> map = {};

    for (final f in _mine) {
      final p = Format.findPeriodForFineDate(fineDate: f.fineDate, periods: periodsSorted);
      final semester = p?.semester ?? 'Unbekannt';
      final pid = p?.id ?? 'unknown';

      map.putIfAbsent(semester, () => <String, List<FineDto>>{});
      map[semester]!.putIfAbsent(pid, () => <FineDto>[]);
      map[semester]![pid]!.add(f);
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
          if (a == 'unknown') return 1;
          if (b == 'unknown') return -1;
          final pa = _periodById[a];
          final pb = _periodById[b];
          final da = pa == null ? DateTime.fromMillisecondsSinceEpoch(0) : Format.parseIsoToLocal(pa.startAt);
          final db = pb == null ? DateTime.fromMillisecondsSinceEpoch(0) : Format.parseIsoToLocal(pb.startAt);
          return db.compareTo(da);
        });

      final periods = <_PeriodGroup>[];
      for (final pid in periodIds) {
        final fines = [...periodMap[pid]!]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
        ? 'Conventsperiode: Unbekannt'
        : 'Conventsperiode: ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}';

    final sumCents = pg.fines.fold<int>(0, (acc, f) {
      final amount = f.amountCents ?? 0;
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
                  titleAlignment: ListTileTitleAlignment.center,
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
    final creator = userLabel(f.creatorUserId);

    return 'Betrag: ${Format.centsToEur(amount)} · Creator: $creator\n'
        'Beihängungsdatum: ${Format.dateOnlyShort(f.fineDate)}';
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
