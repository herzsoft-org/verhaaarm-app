import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class FinesListPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const FinesListPage({super.key, required this.api, required this.authStore});

  @override
  State<FinesListPage> createState() => _FinesListPageState();
}

class _FinesListPageState extends State<FinesListPage> {
  bool _loading = true;

  List<FineDto> _fines = const [];
  List<ConventPeriodDto> _periods = const [];
  Map<String, UserPickerDto> _userById = const {};
  Map<String, FineCatalogItemDto> _catalogById = const {};
  Map<String, bool> _fineHasPhotos = const {};

  String? _currentPeriodId;
  String? _currentSemester;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Set<AppRole> get _roles => widget.authStore.currentRoles;

  bool get _isTreasurerOnlyCreator {
    final roles = _roles;
    return roles.contains(AppRole.treasurer) &&
        !Roles.canCreateOfficialFine(roles);
  }

  bool _canResolveAllTargetUsers(FineDto f) {
    return f.targetUserIds.every(_userById.containsKey);
  }

  bool _isAttendanceSystemTitle(String title) {
    final t = title.trim().toLowerCase();
    return t == 'absent' || t == 'late';
  }

  bool _isAttendanceFine(FineDto f) {
    if (f.type != FineType.catalog) return false;
    final cid = f.catalogItemId;
    if (cid == null) return false;
    final item = _catalogById[cid];
    if (item == null) return false;
    return _isAttendanceSystemTitle(item.title);
  }

  bool _hasFinePhotos(FineDto f) {
    return _fineHasPhotos[f.id] ?? false;
  }

  static ({int year, int term}) _semesterKey(String semester) {
    final s = semester.trim().toUpperCase();
    if (s.startsWith('SS')) {
      final yy =
          int.tryParse(s.substring(2).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
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
    if (f.type == FineType.catalog && f.catalogItemId != null) {
      final item = _catalogById[f.catalogItemId!];
      if (item != null && item.title.trim().isNotEmpty) {
        return item.title.trim();
      }
    }
    final r = (f.reason ?? '').trim();
    if (r.isNotEmpty) return r;
    return 'Beihängung';
  }

  ConventPeriodDto? _detectCurrentPeriod(List<ConventPeriodDto> periods) {
    for (final p in periods) {
      if (p.active == true) return p;
    }

    final now = DateTime.now();
    for (final p in periods) {
      final start = Format.parseIsoToLocal(p.startAt);
      final end = Format.parseIsoToLocal(p.endAt);
      final startDay = DateTime(start.year, start.month, start.day);
      final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
      if (!now.isBefore(startDay) && !now.isAfter(endDay)) {
        return p;
      }
    }

    return null;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final periodsFuture = widget.api.listPeriods();
      final finesFuture = widget.api.listFines();
      final usersFuture = widget.api.pickerUsers();
      final catalogFuture = widget.api.listFineCatalog(active: null);

      final periods = await periodsFuture;
      final fines = await finesFuture;

      final users = await usersFuture;
      users.sort((a, b) => a.displayName.compareTo(b.displayName));
      final userById = {for (final u in users) u.id: u};

      Map<String, FineCatalogItemDto> catalogById = const {};
      try {
        final catalog = await catalogFuture;
        catalogById = {for (final c in catalog) c.id: c};
      } catch (_) {
        catalogById = const {};
      }

      final currentPeriod = _detectCurrentPeriod(periods);
      final fineHasPhotos = {
        for (final fine in fines)
          fine.id: fine.hasPhotos == true || (fine.photoCount ?? 0) > 0,
      };

      if (!mounted) return;
      setState(() {
        _periods = periods;
        _userById = userById;
        _catalogById = catalogById;
        _fines = fines;
        _fineHasPhotos = fineHasPhotos;
        _currentPeriodId = currentPeriod?.id;
        _currentSemester = currentPeriod?.semester;
      });

      _loadPhotoIndicators(fines, fineHasPhotos);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beihängungen laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPhotoIndicators(
    List<FineDto> fines,
    Map<String, bool> initial,
  ) async {
    final next = Map<String, bool>.from(initial);

    for (final fine in fines) {
      try {
        final photos = await widget.api.listFinePhotos(fine.id);
        next[fine.id] = photos.isNotEmpty;
      } catch (_) {
        next[fine.id] = next[fine.id] ?? false;
      }

      if (!mounted) return;
      setState(() => _fineHasPhotos = Map.unmodifiable(next));
    }
  }

  Future<void> _openCreateFromPlus() async {
    if (_loading) return;

    final roles = _roles;

    if (Roles.canCreateOfficialFine(roles)) {
      await context.push('/fines/new');

      if (!mounted) return;
      await _load();
      return;
    }

    if (roles.contains(AppRole.treasurer)) {
      final changed = await context.push<bool>('/suggestions/new');

      if (!mounted) return;
      if (changed == true) {
        await _load();
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Keine Berechtigung zum Hinzufügen.')),
    );
  }

  Future<void> _openFineDetail(String id) async {
    await context.push('/fines/$id');

    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _buildGrouped();

    return AppScaffold(
      title: 'Beihängungen',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: _isTreasurerOnlyCreator
              ? 'Beihängung vorschlagen'
              : 'Beihängung erstellen',
          icon: const Icon(Icons.add_rounded),
          onPressed: _loading ? null : _openCreateFromPlus,
        ),
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
                  if (grouped.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Keine Perioden gefunden.'),
                    ),
                  for (final sem in grouped)
                    _SemesterSection(
                      semester: sem.semester,
                      periods: sem.periods,
                      fineTitle: _fineTitle,
                      userLabel: _userLabel,
                      onTapFine: _openFineDetail,
                      isAttendanceFine: _isAttendanceFine,
                      hasFinePhotos: _hasFinePhotos,
                      initiallyExpanded: sem.semester == _currentSemester,
                      currentPeriodId: _currentPeriodId,
                    ),
                ],
              ),
            ),
    );
  }

  List<_SemesterGroup> _buildGrouped() {
    final periodsSorted = [..._periods]
      ..sort((a, b) => b.startDateLocal.compareTo(a.startDateLocal));

    final Map<String, List<FineDto>> finesByPeriodId = {};
    for (final f in _fines) {
      if (!_canResolveAllTargetUsers(f)) continue;

      final p = Format.findPeriodForFineDate(
        fineDate: f.fineDate,
        periods: periodsSorted,
      );
      final pid = p?.id ?? 'unknown';
      finesByPeriodId.putIfAbsent(pid, () => <FineDto>[]);
      finesByPeriodId[pid]!.add(f);
    }

    final Map<String, List<ConventPeriodDto>> periodsBySemester = {};
    for (final p in _periods) {
      periodsBySemester.putIfAbsent(p.semester, () => <ConventPeriodDto>[]);
      periodsBySemester[p.semester]!.add(p);
    }

    final semesters = periodsBySemester.keys.toList()
      ..sort((a, b) {
        final ka = _semesterKey(a);
        final kb = _semesterKey(b);
        final c1 = kb.year.compareTo(ka.year);
        if (c1 != 0) return c1;
        return kb.term.compareTo(ka.term);
      });

    final result = <_SemesterGroup>[];
    for (final sem in semesters) {
      final ps = [...periodsBySemester[sem]!]
        ..sort((a, b) {
          final da = Format.parseIsoToLocal(a.startAt);
          final db = Format.parseIsoToLocal(b.startAt);
          return db.compareTo(da);
        });

      final periodGroups = <_PeriodGroup>[];
      for (final p in ps) {
        final fines = [...(finesByPeriodId[p.id] ?? const <FineDto>[])]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final isCurrentPeriod = p.id == _currentPeriodId;

        // only keep empty period visible if it is the current one
        if (fines.isEmpty && !isCurrentPeriod) continue;

        periodGroups.add(_PeriodGroup(period: p, fines: fines));
      }

      final unknownFines = [
        ...(finesByPeriodId['unknown'] ?? const <FineDto>[]),
      ];
      if (unknownFines.isNotEmpty) {
        unknownFines.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        periodGroups.add(
          _PeriodGroup(
            period: ConventPeriodDto(
              id: 'unknown',
              semester: sem,
              startAt: DateTime.fromMillisecondsSinceEpoch(
                0,
              ).toUtc().toIso8601String(),
              endAt: DateTime.fromMillisecondsSinceEpoch(
                0,
              ).toUtc().toIso8601String(),
              active: false,
              locked: false,
            ),
            fines: unknownFines,
          ),
        );
      }

      if (periodGroups.isEmpty) continue;

      result.add(_SemesterGroup(semester: sem, periods: periodGroups));
    }

    if (result.isEmpty && (finesByPeriodId['unknown']?.isNotEmpty ?? false)) {
      final unknownFines = [
        ...(finesByPeriodId['unknown'] ?? const <FineDto>[]),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      result.add(
        _SemesterGroup(
          semester: 'Unbekannt',
          periods: [
            _PeriodGroup(
              period: ConventPeriodDto(
                id: 'unknown',
                semester: 'Unbekannt',
                startAt: DateTime.fromMillisecondsSinceEpoch(
                  0,
                ).toUtc().toIso8601String(),
                endAt: DateTime.fromMillisecondsSinceEpoch(
                  0,
                ).toUtc().toIso8601String(),
                active: false,
                locked: false,
              ),
              fines: unknownFines,
            ),
          ],
        ),
      );
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
  final ConventPeriodDto period;
  final List<FineDto> fines;

  _PeriodGroup({required this.period, required this.fines});
}

class _SemesterSection extends StatelessWidget {
  final String semester;
  final List<_PeriodGroup> periods;

  final String Function(FineDto) fineTitle;
  final String Function(String userId) userLabel;
  final void Function(String fineId) onTapFine;
  final bool Function(FineDto) isAttendanceFine;
  final bool Function(FineDto) hasFinePhotos;
  final bool initiallyExpanded;
  final String? currentPeriodId;

  const _SemesterSection({
    required this.semester,
    required this.periods,
    required this.fineTitle,
    required this.userLabel,
    required this.onTapFine,
    required this.isAttendanceFine,
    required this.hasFinePhotos,
    required this.initiallyExpanded,
    required this.currentPeriodId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: PageStorageKey('semester-$semester'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        title: Text(semester, style: Theme.of(context).textTheme.titleLarge),
        children: [
          for (final pg in periods)
            _PeriodSection(
              period: pg.period,
              fines: pg.fines,
              fineTitle: fineTitle,
              userLabel: userLabel,
              onTapFine: onTapFine,
              isAttendanceFine: isAttendanceFine,
              hasFinePhotos: hasFinePhotos,
              initiallyExpanded: pg.period.id == currentPeriodId,
            ),
        ],
      ),
    );
  }
}

class _PeriodSection extends StatelessWidget {
  final ConventPeriodDto period;
  final List<FineDto> fines;

  final String Function(FineDto) fineTitle;
  final String Function(String userId) userLabel;
  final void Function(String fineId) onTapFine;
  final bool Function(FineDto) isAttendanceFine;
  final bool Function(FineDto) hasFinePhotos;
  final bool initiallyExpanded;

  const _PeriodSection({
    required this.period,
    required this.fines,
    required this.fineTitle,
    required this.userLabel,
    required this.onTapFine,
    required this.isAttendanceFine,
    required this.hasFinePhotos,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final header = (period.id == 'unknown')
        ? 'Conventsperiode: Unbekannt (Datum passt zu keiner Conventsperiode)'
        : 'Conventsperiode: ${Format.dateShort(period.startAt)} – ${Format.dateShort(period.endAt)}';

    final flags = <Widget>[];
    if (period.active == true) {
      flags.add(const _Chip(text: 'Aktiv', icon: Icons.play_arrow_rounded));
    }
    if (period.locked == true) {
      flags.add(const _Chip(text: 'Locked', icon: Icons.lock_rounded));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        child: ExpansionTile(
          key: PageStorageKey('period-${period.id}'),
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          title: Text(header, style: Theme.of(context).textTheme.titleSmall),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...flags,
              const SizedBox(width: 8),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
          children: [
            if (fines.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Keine Beihängungen in der aktuellen Conventsperiode',
                  ),
                ),
              )
            else
              for (final f in fines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      titleAlignment: ListTileTitleAlignment.center,
                      leading: const Icon(Icons.gavel_rounded),
                      title: Text(fineTitle(f)),
                      subtitle: Text(_subtitleForFine(f)),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasFinePhotos(f))
                            Icon(
                              Icons.photo_camera_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          if (hasFinePhotos(f)) const SizedBox(width: 8),
                          if (isAttendanceFine(f))
                            const Chip(
                              label: Text('Auto'),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (isAttendanceFine(f)) const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      onTap: () => onTapFine(f.id),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _subtitleForFine(FineDto f) {
    final amount = f.amountCents ?? 0;

    final targets = f.targetUserIds;
    String targetsText;
    if (targets.isEmpty) {
      targetsText = '—';
    } else if (targets.length == 1) {
      targetsText = userLabel(targets.first);
    } else if (targets.length == 2) {
      targetsText = '${userLabel(targets[0])}, ${userLabel(targets[1])}';
    } else {
      targetsText =
          '${userLabel(targets[0])}, ${userLabel(targets[1])} (+${targets.length - 2})';
    }

    return 'Betrag: ${Format.centsToEur(amount)} · Bbr.: $targetsText\n'
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
