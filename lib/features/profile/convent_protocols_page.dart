import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class ConventProtocolsPage extends StatefulWidget {
  final ApiClient api;

  const ConventProtocolsPage({super.key, required this.api});

  @override
  State<ConventProtocolsPage> createState() => _ConventProtocolsPageState();
}

class _ConventProtocolsPageState extends State<ConventProtocolsPage> {
  bool _loading = true;

  /// Visible periods only: no future periods.
  List<ConventPeriodDto> _periods = const [];

  /// Full backend list, used only to determine whether a visible period is
  /// really the first/last protocol of a semester.
  List<ConventPeriodDto> _allPeriods = const [];

  @override
  void initState() {
    super.initState();
    _load();
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

  static List<ConventPeriodDto> _filterUntilCurrentPeriod(
    List<ConventPeriodDto> periods,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return periods.where((p) {
      final start = p.startDateLocal;
      return !start.isAfter(today);
    }).toList();
  }

  static String? _currentPeriodId(List<ConventPeriodDto> periods) {
    if (periods.isEmpty) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final p in periods) {
      if (p.active) return p.id;
    }

    for (final p in periods) {
      final start = p.startDateLocal;
      final end = p.endDateLocal;

      final startsBeforeOrToday = !start.isAfter(today);
      final endsAfterOrToday = !end.isBefore(today);

      if (startsBeforeOrToday && endsAfterOrToday) {
        return p.id;
      }
    }

    final visible =
        periods.where((p) => !p.startDateLocal.isAfter(today)).toList()
          ..sort((a, b) {
            final byStart = b.startAt.compareTo(a.startAt);
            if (byStart != 0) return byStart;
            return b.endAt.compareTo(a.endAt);
          });

    return visible.isEmpty ? null : visible.first.id;
  }

  static bool _isPastMissingProtocol(
    ConventPeriodDto period,
    String? currentPeriodId,
  ) {
    if (period.hasProtocolPdf) return false;
    if (period.id == currentPeriodId) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return period.endDateLocal.isBefore(today);
  }

  static String? _currentSemester(List<ConventPeriodDto> periods) {
    if (periods.isEmpty) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final p in periods) {
      if (p.active) return p.semester;
    }

    for (final p in periods) {
      final start = p.startDateLocal;
      final end = p.endDateLocal;

      final startsBeforeOrToday = !start.isAfter(today);
      final endsAfterOrToday = !end.isBefore(today);

      if (startsBeforeOrToday && endsAfterOrToday) {
        return p.semester;
      }
    }

    final visible =
        periods.where((p) => !p.startDateLocal.isAfter(today)).toList()
          ..sort((a, b) {
            final byStart = b.startAt.compareTo(a.startAt);
            if (byStart != 0) return byStart;
            return b.endAt.compareTo(a.endAt);
          });

    if (visible.isNotEmpty) return visible.first.semester;

    return null;
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);

    try {
      final periods = await widget.api.listPeriods();
      final visiblePeriods = _filterUntilCurrentPeriod(periods);

      visiblePeriods.sort((a, b) {
        final ka = _semesterKey(a.semester);
        final kb = _semesterKey(b.semester);

        final byYear = kb.year.compareTo(ka.year);
        if (byYear != 0) return byYear;

        final byTerm = kb.term.compareTo(ka.term);
        if (byTerm != 0) return byTerm;

        final byStart = b.startAt.compareTo(a.startAt);
        if (byStart != 0) return byStart;

        return b.endAt.compareTo(a.endAt);
      });

      if (!mounted) return;
      setState(() {
        _allPeriods = periods;
        _periods = visiblePeriods;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conventsprotokolle konnten nicht geladen werden: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openProtocol(ConventPeriodDto period) async {
    final changed = await context.push<bool>(
      '/convent-protocols/${period.id}',
      extra: period,
    );

    if (changed == true && mounted) {
      await _load(force: true);
    }
  }

  Map<String, List<ConventPeriodDto>> _groupBySemester() {
    final grouped = <String, List<ConventPeriodDto>>{};

    for (final p in _periods) {
      grouped.putIfAbsent(p.semester, () => <ConventPeriodDto>[]).add(p);
    }

    for (final list in grouped.values) {
      list.sort((a, b) {
        // Latest visible period at the top inside each semester.
        final byStart = b.startAt.compareTo(a.startAt);
        if (byStart != 0) return byStart;
        return b.endAt.compareTo(a.endAt);
      });
    }

    return grouped;
  }

  Map<String, List<ConventPeriodDto>> _groupAllBySemester() {
    final grouped = <String, List<ConventPeriodDto>>{};

    for (final p in _allPeriods) {
      grouped.putIfAbsent(p.semester, () => <ConventPeriodDto>[]).add(p);
    }

    for (final list in grouped.values) {
      list.sort((a, b) {
        // Chronological order:
        // first existing period of semester at index 0,
        // last existing period of semester at index length - 1.
        final byStart = a.startAt.compareTo(b.startAt);
        if (byStart != 0) return byStart;
        return a.endAt.compareTo(b.endAt);
      });
    }

    return grouped;
  }

  List<String> _sortedSemesters(Map<String, List<ConventPeriodDto>> grouped) {
    return grouped.keys.toList()..sort((a, b) {
      final ka = _semesterKey(a);
      final kb = _semesterKey(b);

      final byYear = kb.year.compareTo(ka.year);
      if (byYear != 0) return byYear;

      return kb.term.compareTo(ka.term);
    });
  }

  String _protocolTitleForPeriod({
    required ConventPeriodDto period,
    required List<ConventPeriodDto> allPeriodsInSemester,
  }) {
    final chronologicalIndex = allPeriodsInSemester.indexWhere(
      (p) => p.id == period.id,
    );

    if (chronologicalIndex < 0) {
      return 'Conventsprotokoll';
    }

    if (allPeriodsInSemester.length <= 1) {
      return 'An-/Abconventsprotokoll';
    }

    if (chronologicalIndex == 0) {
      return 'Anconventsprotokoll';
    }

    if (chronologicalIndex == allPeriodsInSemester.length - 1) {
      return 'Abconventsprotokoll';
    }

    // Middle protocols start at 1 after the Anconventsprotokoll.
    return '$chronologicalIndex. Conventsprotokoll';
  }

  Widget _buildFutureInfoCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.update_rounded, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Zukünftige Conventsperioden erscheinen automatisch, sobald sie erreicht werden. '
                'Die aktuellste sichtbare Periode ist immer die laufende Conventsperiode.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    ConventPeriodDto p, {
    required bool isCurrentPeriod,
    required bool isPastMissingProtocol,
  }) {
    final cs = Theme.of(context).colorScheme;

    final Color bg;
    final Color fg;
    final String text;

    if (isCurrentPeriod) {
      bg = cs.primaryContainer.withValues(alpha: 0.75);
      fg = cs.onPrimaryContainer;
      text = p.hasProtocolPdf
          ? 'Aktuelle Periode · Vorhanden'
          : 'Aktuelle Periode · Nicht hinterlegt';
    } else if (p.hasProtocolPdf) {
      bg = cs.primaryContainer.withValues(alpha: 0.75);
      fg = cs.onPrimaryContainer;
      text = 'Vorhanden';
    } else if (isPastMissingProtocol) {
      bg = cs.errorContainer.withValues(alpha: 0.85);
      fg = cs.onErrorContainer;
      text = 'Fehlt';
    } else {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
      text = 'Nicht hinterlegt';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }

  Widget _buildProtocolCard({
    required ConventPeriodDto period,
    required String title,
    required bool isCurrentPeriod,
    required bool isPastMissingProtocol,
  }) {
    final cs = Theme.of(context).colorScheme;

    final iconColor = isPastMissingProtocol
        ? cs.onErrorContainer
        : period.hasProtocolPdf
        ? cs.onPrimaryContainer
        : cs.onSurfaceVariant;

    final iconBg = isPastMissingProtocol
        ? cs.errorContainer.withValues(alpha: 0.85)
        : period.hasProtocolPdf
        ? cs.primaryContainer
        : cs.surfaceContainerHighest;

    final icon = isPastMissingProtocol
        ? Icons.error_outline_rounded
        : period.hasProtocolPdf
        ? Icons.picture_as_pdf_rounded
        : Icons.upload_file_rounded;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openProtocol(period),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${Format.dateShort(period.startAt)} – ${Format.dateShort(period.endAt)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStatusChip(
                      context,
                      period,
                      isCurrentPeriod: isCurrentPeriod,
                      isPastMissingProtocol: isPastMissingProtocol,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterSection({
    required String semester,
    required List<ConventPeriodDto> periods,
    required List<ConventPeriodDto> allPeriodsInSemester,
    required bool isCurrentSemester,
    required String? currentPeriodId,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: isCurrentSemester,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Icon(
          isCurrentSemester
              ? Icons.event_available_rounded
              : Icons.event_note_rounded,
          color: isCurrentSemester ? cs.primary : cs.onSurfaceVariant,
        ),
        title: Text(semester, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          isCurrentSemester
              ? 'Aktuelles Semester'
              : '${periods.length} ${periods.length == 1 ? 'Protokoll' : 'Protokolle'}',
        ),
        children: [
          for (final entry in periods.asMap().entries)
            _buildProtocolCard(
              period: entry.value,
              title: _protocolTitleForPeriod(
                period: entry.value,
                allPeriodsInSemester: allPeriodsInSemester,
              ),
              isCurrentPeriod: entry.value.id == currentPeriodId,
              isPastMissingProtocol: _isPastMissingProtocol(
                entry.value,
                currentPeriodId,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Keine Conventsperioden gefunden.'),
      ),
    );
  }

  Widget _buildList() {
    final grouped = _groupBySemester();
    final allGrouped = _groupAllBySemester();
    final semesters = _sortedSemesters(grouped);
    final currentSemester = _currentSemester(_periods);
    final currentPeriodId = _currentPeriodId(_periods);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        _buildFutureInfoCard(context),
        const SizedBox(height: 12),
        for (final semester in semesters)
          _buildSemesterSection(
            semester: semester,
            periods: grouped[semester]!,
            allPeriodsInSemester: allGrouped[semester] ?? grouped[semester]!,
            isCurrentSemester: semester == currentSemester,
            currentPeriodId: currentPeriodId,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Conventsprotokolle',
      showNotificationButton: false,
      showProfileButton: false,
      onRefresh: () => _load(force: true),
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _periods.isEmpty
          ? _buildEmptyState()
          : _buildList(),
    );
  }
}
