import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class PeriodFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  /// null = create
  final String? periodId;

  const PeriodFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.periodId,
  });

  @override
  State<PeriodFormPage> createState() => _PeriodFormPageState();
}

class _PeriodFormPageState extends State<PeriodFormPage> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  String? _semesterValue;

  /// date-only (local midnight)
  DateTime? _startDateLocal;
  DateTime? _endDateLocal;

  // --- Semester generation config ---
  // Start at SS25
  static const int _startYear = 2025;
  static const bool _startIsSummer = true; // SS25
  static const int _count = 50;

  static List<String> _buildSemesterOptions({
    required int startYear,
    required bool startIsSummer,
    required int count,
  }) {
    final out = <String>[];
    var year = startYear;
    var isSummer = startIsSummer;

    for (var i = 0; i < count; i++) {
      if (isSummer) {
        out.add('SS${(year % 100).toString().padLeft(2, '0')}');
        isSummer = false;
      } else {
        final a = (year % 100).toString().padLeft(2, '0');
        final b = ((year + 1) % 100).toString().padLeft(2, '0');
        out.add('WS$a/$b');
        year = year + 1;
        isSummer = true;
      }
    }

    return out;
  }

  late final List<String> _semesterOptions = _buildSemesterOptions(
    startYear: _startYear,
    startIsSummer: _startIsSummer,
    count: _count,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  static DateTime _parseLocalDate(String s) {
    final parts = s.split('-');
    if (parts.length != 3) throw FormatException('Invalid date: $s');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime(y, m, d);
  }

  static String _fmtLocalDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _guessSemesterFromDate(DateTime localDate) {
    // SS = Apr-Sep, WS = Oct-Mar (WS label uses start year)
    final y = localDate.year;
    final m = localDate.month;

    if (m >= 4 && m <= 9) {
      return 'SS${(y % 100).toString().padLeft(2, '0')}';
    }

    final wsStartYear = (m <= 3) ? (y - 1) : y;
    final a = (wsStartYear % 100).toString().padLeft(2, '0');
    final b = ((wsStartYear + 1) % 100).toString().padLeft(2, '0');
    return 'WS$a/$b';
  }

  String _closestSemesterOption(String desired) {
    final d = desired.trim().toUpperCase();
    if (_semesterOptions.contains(d)) return d;
    return _semesterOptions.isEmpty ? d : _semesterOptions.first;
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final roles = widget.authStore.currentRoles;
      if (!Roles.canManagePeriods(roles)) {
        if (mounted) context.go('/home');
        return;
      }

      if (widget.periodId != null) {
        final p = await widget.api.getPeriod(widget.periodId!);

        if (!mounted) return;
        setState(() {
          _semesterValue = _closestSemesterOption(p.semester);
          _startDateLocal = _parseLocalDate(p.startAt);
          _endDateLocal = _parseLocalDate(p.endAt);
        });
      } else {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final end = today.add(const Duration(days: 7));
        final guess = _guessSemesterFromDate(today);

        if (!mounted) return;
        setState(() {
          _startDateLocal = today;
          _endDateLocal = end;
          _semesterValue = _closestSemesterOption(guess);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickSemester() async {
    final current = _semesterValue ?? (_semesterOptions.isEmpty ? '' : _semesterOptions.first);
    final initialIndex = _semesterOptions.indexOf(current);
    final safeIndex = (initialIndex < 0) ? 0 : initialIndex;

    final nav = Navigator.of(context);

    final res = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        int selected = safeIndex;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Semester auswählen',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () => nav.pop(null),
                          child: const Text('Abbrechen'),
                        ),
                        FilledButton(
                          onPressed: () => nav.pop(_semesterOptions[selected]),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _semesterOptions.length,
                        itemBuilder: (c, i) {
                          final v = _semesterOptions[i];
                          final isSel = i == selected;
                          return ListTile(
                            title: Text(v),
                            trailing: isSel ? const Icon(Icons.check_rounded) : null,
                            onTap: () => setSheetState(() => selected = i),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (res != null) setState(() => _semesterValue = res);
  }

  Future<DateTime?> _pickDate({
    required DateTime? initial,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final init = initial ?? DateTime(now.year, now.month, now.day);

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(init.year, init.month, init.day),
      firstDate: firstDate ?? DateTime(now.year - 1),
      lastDate: lastDate ?? DateTime(now.year + 10),
    );
    if (date == null) return null;

    return DateTime(date.year, date.month, date.day);
  }

  String _fmtLocal(DateTime? d) {
    if (d == null) return '—';
    return Format.dateShort(_fmtLocalDate(d));
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final semester = (_semesterValue ?? '').trim();
    if (semester.isEmpty) {
      setState(() {});
      return;
    }

    final start = _startDateLocal;
    final end = _endDateLocal;
    if (start == null || end == null) return;

    // date-only: allow same day, forbid end < start
    if (end.isBefore(start)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ende darf nicht vor Start liegen.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      if (widget.periodId == null) {
        final req = CreateConventPeriodRequest(
          semester: semester,
          startAt: _fmtLocalDate(start),
          endAt: _fmtLocalDate(end),
        );
        await widget.api.createPeriod(req);
      } else {
        final req = UpdateConventPeriodRequest(
          semester: semester,
          startAt: _fmtLocalDate(start),
          endAt: _fmtLocalDate(end),
        );
        await widget.api.updatePeriod(widget.periodId!, req);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gespeichert.')),
      );
      context.pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data?.toString() ?? e.message ?? 'Unbekannter Fehler';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.periodId != null;
    final semesterMissing = _semesterValue == null || _semesterValue!.trim().isEmpty;

    return AppScaffold(
      title: isEdit ? 'Conventsperiode bearbeiten' : 'Conventsperiode erstellen',
      actions: [
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: (_loading || _saving) ? null : _submit,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _saving ? null : _pickSemester,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Semester',
                          prefixIcon: Icon(Icons.school_rounded),
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                semesterMissing ? 'Semester auswählen' : _semesterValue!,
                              ),
                            ),
                            const Icon(Icons.expand_more_rounded),
                          ],
                        ),
                      ),
                    ),
                    if (semesterMissing) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Semester fehlt.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _saving
                                ? null
                                : () async {
                              final picked = await _pickDate(initial: _startDateLocal);
                              if (!mounted || picked == null) return;
                              setState(() => _startDateLocal = picked);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start (Datum)',
                                prefixIcon: Icon(Icons.calendar_month_rounded),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(_fmtLocal(_startDateLocal)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _saving
                                ? null
                                : () async {
                              final picked = await _pickDate(initial: _endDateLocal);
                              if (!mounted || picked == null) return;
                              setState(() => _endDateLocal = picked);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Ende (Datum)',
                                prefixIcon: Icon(Icons.calendar_month_rounded),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(_fmtLocal(_endDateLocal)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
