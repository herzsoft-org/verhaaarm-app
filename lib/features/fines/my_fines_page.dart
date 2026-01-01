import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/roles.dart';
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
  static const _kMyFinesUsers = 'myfines.users';
  static const _kMyFinesCatalog = 'myfines.catalog';
  static const _kMyFinesPeriods = 'myfines.periods'; // NEW (for grouping)

  // NEW: current user id (for filtering)
  static const _kMyFinesMeUserId = 'myfines.me.userId';

  bool _loading = true;
  bool _refreshing = false;

  // false => current active period only (default)
  // true  => all fines across all periods (past + future), grouped
  bool _showAllPeriods = false;

  ConventPeriodDto? _activePeriod;
  UserBalanceDto? _balance;

  List<FineDto> _allFines = const [];
  List<FineDto> _visibleFines = const [];

  // NEW: periods for grouping
  Map<String, ConventPeriodDto> _periodById = const {};
  List<ConventPeriodDto> _periodsSorted = const [];

  Map<String, UserPickerDto> _userById = const {};
  Map<String, FineCatalogItemDto> _catalogById = const {};

  // NEW: "me" user id for filtering
  String? _meUserId;

  bool _isNoActivePeriodError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      return code == 404;
    }
    return false;
  }

  // ---------- cache encode/decode ----------
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
    'id': b.userId, // legacy callers
    'balanceCents': b.balanceCents,
    'balanceFormatted': b.balanceFormatted,
  };

  UserBalanceDto _decodeBalance(Object json) =>
      UserBalanceDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeUser(UserPickerDto u) => {
    'id': u.id,
    'username': u.username,
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
    'type': f.type.name,
    'suggesterUserId': f.suggesterUserId,
    'acceptedFromSuggestionId': f.acceptedFromSuggestionId,
  };

  FineDto _decodeFine(Object json) =>
      FineDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeCatalogItem(FineCatalogItemDto c) => {
    'id': c.id,
    'title': c.title,
    'active': c.active,
    'defaultAmountCents': c.defaultAmountCents,
  };

  FineCatalogItemDto _decodeCatalogItem(Object json) =>
      FineCatalogItemDto.fromJson((json as Map).cast<String, dynamic>());

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _userLabel(String id) => _userById[id]?.displayName ?? id;

  String _fineTitle(FineDto f) {
    if (f.type == FineType.catalog && f.catalogItemId != null) {
      final item = _catalogById[f.catalogItemId!];
      if (item != null && item.title.trim().isNotEmpty) return item.title.trim();
    }
    final r = (f.reason ?? '').trim();
    if (r.isNotEmpty) return r;
    return 'Beihängung';
  }

  bool _isFineInPeriod(FineDto f, ConventPeriodDto p) {
    // backend semantics (now): inclusive range
    // startAt <= fineDate <= endAt
    final d = _parseLocalDateOnly(f.fineDate);
    final start = p.startDateLocal;
    final end = p.endDateLocal;
    return !d.isBefore(start) && !d.isAfter(end);
  }

  ConventPeriodDto? _periodForFine(FineDto f) {
    final d = _parseLocalDateOnly(f.fineDate);
    for (final p in _periodsSorted) {
      final start = p.startDateLocal;
      final end = p.endDateLocal; // inclusive
      if (!d.isBefore(start) && !d.isAfter(end)) return p;
    }
    return null;
  }

  // NEW: strict filter to "my" fines only (targetUserIds contains me)
  bool _isMyFine(FineDto f, String? meUserId) {
    final me = (meUserId ?? '').trim();
    if (me.isEmpty) return false;
    return f.targetUserIds.contains(me);
  }

  List<FineDto> _computeVisibleFines({
    required ConventPeriodDto? activePeriod,
    required List<FineDto> all,
    required bool showAllPeriods,
    required String? meUserId,
  }) {
    Iterable<FineDto> it = all;

    // NEW: always filter to "my fines"
    it = it.where((f) => _isMyFine(f, meUserId));

    if (!showAllPeriods) {
      if (activePeriod == null) {
        it = const <FineDto>[];
      } else {
        it = it.where((f) => _isFineInPeriod(f, activePeriod));
      }
    }

    final list = it.toList(growable: false);

    // Sort: fineDate desc, then createdAt desc
    list.sort((a, b) {
      final da = _parseLocalDateOnly(a.fineDate);
      final db = _parseLocalDateOnly(b.fineDate);
      final c1 = db.compareTo(da);
      if (c1 != 0) return c1;
      return b.createdAt.compareTo(a.createdAt);
    });

    return list;
  }

  // ---------- grouping ----------
  List<_SemesterGroup> _buildGroupedBySemesterAndPeriod(List<FineDto> fines) {
    final Map<String, Map<String, List<FineDto>>> map = {};

    for (final f in fines) {
      final p = _periodForFine(f);
      final semester = p?.semester ?? 'Unbekannt';
      final pid = p?.id ?? 'unknown';

      map.putIfAbsent(semester, () => {});
      map[semester]!.putIfAbsent(pid, () => []);
      map[semester]![pid]!.add(f);
    }

    final now = DateTime.now();

    DateTime semesterSortKey(String sem) {
      final periodMap = map[sem]!;
      final periods = periodMap.keys
          .map((pid) => _periodById[pid])
          .whereType<ConventPeriodDto>()
          .toList(growable: false);
      if (periods.isEmpty) return DateTime.fromMillisecondsSinceEpoch(1 << 62);

      final starts =
      periods.map((p) => p.startDateLocal).toList(growable: false);
      final futureStarts = starts.where((d) => !d.isBefore(now)).toList(
        growable: false,
      )..sort();
      if (futureStarts.isNotEmpty) return futureStarts.first;

      final pastStarts =
      starts.where((d) => d.isBefore(now)).toList(growable: false)
        ..sort();
      return pastStarts.isNotEmpty
          ? pastStarts.last
          : DateTime.fromMillisecondsSinceEpoch(1 << 62);
    }

    int semesterIsFuture(String sem) {
      final periodMap = map[sem]!;
      final periods = periodMap.keys
          .map((pid) => _periodById[pid])
          .whereType<ConventPeriodDto>()
          .toList(growable: false);
      if (periods.isEmpty) return 2;

      final anyFutureOrCurrent = periods.any((p) => !p.endDateLocal.isBefore(now));
      return anyFutureOrCurrent ? 0 : 1;
    }

    final semesters = map.keys.toList()
      ..sort((a, b) {
        final fa = semesterIsFuture(a);
        final fb = semesterIsFuture(b);
        final c0 = fa.compareTo(fb);
        if (c0 != 0) return c0;

        final da = semesterSortKey(a);
        final db = semesterSortKey(b);
        final c1 = da.compareTo(db);
        if (c1 != 0) return c1;

        return a.compareTo(b);
      });

    final result = <_SemesterGroup>[];
    for (final sem in semesters) {
      final periodMap = map[sem]!;
      final periodIds = periodMap.keys.toList()
        ..sort((a, b) {
          if (a == 'unknown' && b != 'unknown') return 1;
          if (b == 'unknown' && a != 'unknown') return -1;

          final pa = _periodById[a];
          final pb = _periodById[b];

          final da = pa == null
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : pa.startDateLocal;
          final db = pb == null
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : pb.startDateLocal;

          final aCurrentOrFuture = pa != null && !pa.endDateLocal.isBefore(now);
          final bCurrentOrFuture = pb != null && !pb.endDateLocal.isBefore(now);

          if (aCurrentOrFuture != bCurrentOrFuture) {
            return aCurrentOrFuture ? -1 : 1;
          }
          if (aCurrentOrFuture && bCurrentOrFuture) return da.compareTo(db);
          return db.compareTo(da);
        });

      final periods = <_PeriodGroup>[];
      for (final pid in periodIds) {
        final list = [...periodMap[pid]!];

        // inside each period: latest first
        list.sort((a, b) {
          final da = _parseLocalDateOnly(a.fineDate);
          final db = _parseLocalDateOnly(b.fineDate);
          final c1 = db.compareTo(da);
          if (c1 != 0) return c1;
          return b.createdAt.compareTo(a.createdAt);
        });

        periods.add(_PeriodGroup(periodId: pid, fines: list));
      }

      result.add(_SemesterGroup(semester: sem, periods: periods));
    }

    return result;
  }

  // ---------- load ----------
  Future<void> _load({bool force = false}) async {
    try {
      // NEW: load cached me user id first (prevents showing "all fines" for admins)
      final cMe = await AppCache.I.entryOrLoadPersisted<String>(
        _kMyFinesMeUserId,
        decode: (json) => json.toString(),
      );
      if (cMe != null && (cMe.value).trim().isNotEmpty) {
        _meUserId = cMe.value.trim();
      }

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
        decode: (json) =>
            (json as List).map((e) => _decodeFine(e as Object)).toList(growable: false),
      );
      final cUsers = await AppCache.I.entryOrLoadPersisted<List<UserPickerDto>>(
        _kMyFinesUsers,
        decode: (json) =>
            (json as List).map((e) => _decodeUser(e as Object)).toList(growable: false),
      );
      final cCatalog = await AppCache.I.entryOrLoadPersisted<List<FineCatalogItemDto>>(
        _kMyFinesCatalog,
        decode: (json) => (json as List)
            .map((e) => _decodeCatalogItem(e as Object))
            .toList(growable: false),
      );
      final cPeriods = await AppCache.I.entryOrLoadPersisted<List<ConventPeriodDto>>(
        _kMyFinesPeriods,
        decode: (json) =>
            (json as List).map((e) => _decodePeriod(e as Object)).toList(growable: false),
      );

      final hasAnyCache = (cMe != null) ||
          (cPeriod != null) ||
          (cBal != null) ||
          (cFines != null) ||
          (cUsers != null) ||
          (cCatalog != null) ||
          (cPeriods != null);

      if (hasAnyCache && mounted) {
        final users = List<UserPickerDto>.from(cUsers?.value ?? const <UserPickerDto>[]);
        final catalog =
        List<FineCatalogItemDto>.from(cCatalog?.value ?? const <FineCatalogItemDto>[]);
        final periods = List<ConventPeriodDto>.from(cPeriods?.value ?? const <ConventPeriodDto>[])
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

        final userById = {for (final u in users) u.id: u};
        final catalogById = {for (final c in catalog) c.id: c};
        final periodById = {for (final p in periods) p.id: p};

        final activePeriod = cPeriod?.value;
        final allFines = cFines?.value ?? const <FineDto>[];

        final visible = _computeVisibleFines(
          activePeriod: activePeriod,
          all: allFines,
          showAllPeriods: _showAllPeriods,
          meUserId: _meUserId,
        );

        setState(() {
          _activePeriod = activePeriod;
          _balance = cBal?.value;
          _allFines = allFines;
          _visibleFines = visible;
          _userById = userById;
          _catalogById = catalogById;
          _periodsSorted = periods;
          _periodById = periodById;
          _loading = false;
        });
      }

      final cacheFresh = (cFines != null && cFines.isFresh(_ttlMyFines)) &&
          (cUsers != null && cUsers.isFresh(_ttlMyFines)) &&
          (cCatalog != null && cCatalog.isFresh(_ttlMyFines)) &&
          (cPeriods != null && cPeriods.isFresh(_ttlMyFines)) &&
          (cMe != null && cMe.isFresh(_ttlMyFines));

      if (!force && cacheFresh) return;

      final showFullSpinner = !hasAnyCache;
      if (mounted) {
        setState(() {
          _loading = showFullSpinner;
          _refreshing = !showFullSpinner;
        });
      }

      try {
        // NEW: fetch "me" (authoritative id) and persist it
        try {
          final me = await widget.api.getMe();
          final id = me.id.trim();
          if (id.isNotEmpty) {
            _meUserId = id;
            await AppCache.I.setPersisted<String>(
              _kMyFinesMeUserId,
              id,
              encode: (v) => v,
            );
          }
        } catch (_) {
          // keep existing cached _meUserId if any
        }

        ConventPeriodDto? activePeriod;
        try {
          activePeriod = await widget.api.getActivePeriod();
        } catch (e) {
          if (_isNoActivePeriodError(e)) {
            activePeriod = null;
          } else {
            rethrow;
          }
        }

        UserBalanceDto? bal;
        try {
          bal = await widget.api.getMyBalance();
        } catch (e) {
          if (_isNoActivePeriodError(e)) {
            bal = null;
          } else {
            rethrow;
          }
        }

        final fines = await widget.api.listFines();
        final users = await widget.api.pickerUsers();
        final catalog = await widget.api.listFineCatalog(active: null);

        // NEW: load periods (for grouping)
        final periods = await widget.api.listPeriods();

        await AppCache.I.setPersisted<List<FineDto>>(
          _kMyFinesFines,
          List<FineDto>.unmodifiable(fines),
          encode: (v) => v.map(_encodeFine).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<UserPickerDto>>(
          _kMyFinesUsers,
          List<UserPickerDto>.unmodifiable(users),
          encode: (v) => v.map(_encodeUser).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<FineCatalogItemDto>>(
          _kMyFinesCatalog,
          List<FineCatalogItemDto>.unmodifiable(catalog),
          encode: (v) => v.map(_encodeCatalogItem).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<ConventPeriodDto>>(
          _kMyFinesPeriods,
          List<ConventPeriodDto>.unmodifiable(periods),
          encode: (v) => v.map(_encodePeriod).toList(growable: false),
        );

        if (activePeriod != null) {
          await AppCache.I.setPersisted<ConventPeriodDto>(
            _kMyFinesActivePeriod,
            activePeriod,
            encode: _encodePeriod,
          );
        } else {
          await AppCache.I.removePersisted(_kMyFinesActivePeriod);
        }

        if (bal != null) {
          await AppCache.I.setPersisted<UserBalanceDto>(
            _kMyFinesBalance,
            bal,
            encode: _encodeBalance,
          );
        } else {
          await AppCache.I.removePersisted(_kMyFinesBalance);
        }

        final periodsSorted = List<ConventPeriodDto>.from(periods)
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
        final periodById = {for (final p in periodsSorted) p.id: p};

        final userById = {for (final u in users) u.id: u};
        final catalogById = {for (final c in catalog) c.id: c};

        final visible = _computeVisibleFines(
          activePeriod: activePeriod,
          all: fines,
          showAllPeriods: _showAllPeriods,
          meUserId: _meUserId,
        );

        if (!mounted) return;
        setState(() {
          _activePeriod = activePeriod;
          _balance = bal;
          _allFines = List<FineDto>.unmodifiable(fines);
          _visibleFines = visible;
          _userById = userById;
          _catalogById = catalogById;
          _periodsSorted = periodsSorted;
          _periodById = periodById;
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

  void _setShowAllPeriods(bool v) {
    if (_showAllPeriods == v) return;
    setState(() {
      _showAllPeriods = v;
      _visibleFines = _computeVisibleFines(
        activePeriod: _activePeriod,
        all: _allFines,
        showAllPeriods: _showAllPeriods,
        meUserId: _meUserId,
      );
    });
  }

  // NEW: who may open fine details from "my fines"
  bool _canOpenFineDetails() {
    final token = widget.api.authStore.accessToken;
    final roles = Roles.fromAccessToken(token);
    return roles.contains(AppRole.admin) ||
        roles.contains(AppRole.senior) ||
        roles.contains(AppRole.housekeeping);
  }

  @override
  Widget build(BuildContext context) {
    final p = _activePeriod;

    // CHANGED: show total balance as a negative number (always prefixed with "-")
    final rawBalanceText = (_balance?.balanceFormatted ?? '').trim();
    final balanceText = rawBalanceText.isEmpty
        ? ''
        : (rawBalanceText.startsWith('-') ? rawBalanceText : '-$rawBalanceText');

    final grouped = _showAllPeriods
        ? _buildGroupedBySemesterAndPeriod(_visibleFines)
        : const <_SemesterGroup>[];

    final canOpenDetails = _canOpenFineDetails();

    return AppScaffold(
      title: 'Meine Beihängungen',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
        IconButton(
          tooltip:
          _showAllPeriods ? 'Nur aktuelle Periode' : 'Alle Perioden anzeigen',
          icon: Icon(_showAllPeriods
              ? Icons.history_toggle_off_rounded
              : Icons.history_rounded),
          onPressed: _loading ? null : () => _setShowAllPeriods(!_showAllPeriods),
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

            // top info row (small icon) like EventsPage pattern
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    _showAllPeriods
                        ? Icons.history_rounded
                        : Icons.event_available_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showAllPeriods
                          ? 'Alle Beihängungen (gruppiert nach Semester/Periode)'
                          : 'Beihängungen in der aktuellen Periode',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),

            // header card (active period + balance)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aktuelle Conventsperiode',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      p == null
                          ? 'Keine aktive Conventsperiode'
                          : '${p.semester} · ${Format.dateOnlyShort(p.startAt)} – ${Format.dateOnlyShort(p.endAt)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Text('Saldo',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      balanceText.isNotEmpty
                          ? balanceText
                          : (p == null ? '—' : '…'),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (!_showAllPeriods && p == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Keine Beihängungen: Es gibt aktuell keine aktive Conventsperiode.\n'
                      'Tippe oben auf das Verlauf-Icon, um alle Beihängungen zu sehen.',
                ),
              )
            else if (_visibleFines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_showAllPeriods
                    ? 'Keine Beihängungen gefunden.'
                    : 'Keine Beihängungen in der aktuellen Conventsperiode gefunden.'),
              )
            else if (!_showAllPeriods)
                for (final f in _visibleFines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: ListTile(
                        titleAlignment: ListTileTitleAlignment.center,
                        leading: const Icon(Icons.gavel_rounded),
                        title: Text(_fineTitle(f)),
                        subtitle: Text(_subtitleForFine(f)),
                        isThreeLine: true,
                        trailing: canOpenDetails
                            ? const Icon(Icons.chevron_right_rounded)
                            : null,
                        onTap: canOpenDetails
                            ? () => context.push('/fines/${f.id}')
                            : null,
                      ),
                    ),
                  )
              else
                for (final sem in grouped)
                  _SemesterSectionFines(
                    semester: sem.semester,
                    periods: sem.periods,
                    periodById: _periodById,
                    fineTitle: _fineTitle,
                    subtitleForFine: _subtitleForFine,
                    canOpenFine: canOpenDetails,
                    onOpenFine: (id) => context.push('/fines/$id'),
                  ),
          ],
        ),
      ),
    );
  }

  DateTime _parseLocalDateOnly(String s) {
    final m =
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return DateTime.fromMillisecondsSinceEpoch(0);
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    return DateTime(y, mo, d);
  }

  String _subtitleForFine(FineDto f) {
    final amount = f.amountCents ?? 0;

    // creatorUserId is non-nullable => no ?? and no toString()
    final creatorId = f.creatorUserId;
    final creatorLabel = creatorId.isEmpty ? '' : _userLabel(creatorId);

    return 'Betrag: ${Format.centsToEur(amount)}\n'
        'Beihängungsdatum: ${Format.dateOnlyShort(f.fineDate)}'
        '${creatorId.isEmpty ? '' : '\nErstellt von: $creatorLabel'}';
  }
}

// ---------- grouping models/widgets ----------
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

class _SemesterSectionFines extends StatelessWidget {
  final String semester;
  final List<_PeriodGroup> periods;
  final Map<String, ConventPeriodDto> periodById;

  final String Function(FineDto f) fineTitle;
  final String Function(FineDto f) subtitleForFine;

  // NEW: permissions for opening details
  final bool canOpenFine;

  final void Function(String fineId) onOpenFine;

  const _SemesterSectionFines({
    required this.semester,
    required this.periods,
    required this.periodById,
    required this.fineTitle,
    required this.subtitleForFine,
    required this.canOpenFine,
    required this.onOpenFine,
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
              _PeriodSectionFines(
                pg: pg,
                period: periodById[pg.periodId],
                fineTitle: fineTitle,
                subtitleForFine: subtitleForFine,
                canOpenFine: canOpenFine,
                onOpenFine: onOpenFine,
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSectionFines extends StatelessWidget {
  final _PeriodGroup pg;
  final ConventPeriodDto? period;

  final String Function(FineDto f) fineTitle;
  final String Function(FineDto f) subtitleForFine;

  // NEW: permissions for opening details
  final bool canOpenFine;

  final void Function(String fineId) onOpenFine;

  const _PeriodSectionFines({
    required this.pg,
    required this.period,
    required this.fineTitle,
    required this.subtitleForFine,
    required this.canOpenFine,
    required this.onOpenFine,
  });

  @override
  Widget build(BuildContext context) {
    final p = period;

    final header = (p == null)
        ? (pg.periodId == 'unknown'
        ? 'Conventsperiode: Unbekannt'
        : 'Conventsperiode: ${pg.periodId}')
        : 'Conventsperiode: ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}';

    final flags = <Widget>[];
    if (p?.active == true) {
      flags.add(const _Chip(text: 'Aktiv', icon: Icons.play_arrow_rounded));
    }
    if (p?.locked == true) {
      flags.add(const _Chip(text: 'Locked', icon: Icons.lock_rounded));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(header, style: Theme.of(context).textTheme.titleSmall),
              ),
              ...flags,
            ],
          ),
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
                  subtitle: Text(subtitleForFine(f)),
                  isThreeLine: true,
                  trailing: canOpenFine ? const Icon(Icons.chevron_right_rounded) : null,
                  onTap: canOpenFine ? () => onOpenFine(f.id) : null,
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
