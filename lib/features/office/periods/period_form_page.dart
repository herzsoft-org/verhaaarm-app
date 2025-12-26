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
  DateTime? _startLocal;
  DateTime? _endLocal;

  // --- Semester generation config ---
  // Start at SS25 (as requested)
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

  static String _guessSemesterFromDate(DateTime local) {
    // SS = Apr-Sep, WS = Oct-Mar (WS label uses start year)
    final y = local.year;
    final m = local.month;

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
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!Roles.canManagePeriods(roles)) {
        if (mounted) context.go('/home');
        return;
      }

      if (widget.periodId != null) {
        final p = await widget.api.getPeriod(widget.periodId!);

        if (!mounted) return;
        setState(() {
          _semesterValue = _closestSemesterOption(p.semester);
          _startLocal = DateTime.parse(p.startAt).toLocal();
          _endLocal = DateTime.parse(p.endAt).toLocal();
        });
      } else {
        final now = DateTime.now().add(const Duration(hours: 2));
        final start = DateTime(now.year, now.month, now.day, now.hour, now.minute);
        final end = start.add(const Duration(days: 7));
        final guess = _guessSemesterFromDate(start);

        if (!mounted) return;
        setState(() {
          _startLocal = start;
          _endLocal = end;
          _semesterValue = _closestSemesterOption(guess);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false); // no return in finally
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

  DateTime _stripSeconds(DateTime dt) => DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  Future<DateTime?> _pickDateTime({
    required DateTime? initial,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final init = initial ?? now.add(const Duration(hours: 2));

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(init.year, init.month, init.day),
      firstDate: firstDate ?? DateTime(now.year - 1),
      lastDate: lastDate ?? DateTime(now.year + 10),
    );
    if (date == null) return null;

    // Fix: avoid using BuildContext after an async gap without checking mounted.
    if (!mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (time == null) return null;

    return _stripSeconds(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  String _fmtLocal(DateTime? dt) {
    if (dt == null) return '—';
    return Format.dateTimeShort(dt.toIso8601String());
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final semester = (_semesterValue ?? '').trim();
    if (semester.isEmpty) {
      setState(() {}); // show error
      return;
    }

    final start = _startLocal;
    final end = _endLocal;
    if (start == null || end == null) return;

    if (!end.isAfter(start)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ende muss nach Start liegen.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      if (widget.periodId == null) {
        final req = CreateConventPeriodRequest(
          semester: semester,
          startAt: start.toUtc().toIso8601String(),
          endAt: end.toUtc().toIso8601String(),
        );
        await widget.api.createPeriod(req);
      } else {
        final req = UpdateConventPeriodRequest(
          semester: semester,
          startAt: start.toUtc().toIso8601String(),
          endAt: end.toUtc().toIso8601String(),
        );
        await widget.api.updatePeriod(widget.periodId!, req);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gespeichert.')),
      );
      context.pop();
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
      if (mounted) setState(() => _saving = false); // no return in finally
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.periodId != null;
    final semesterMissing = _semesterValue == null || _semesterValue!.trim().isEmpty;

    return AppScaffold(
      title: isEdit ? 'Periode bearbeiten' : 'Periode erstellen',
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_arrow_rounded),
                      title: const Text('Start'),
                      subtitle: Text(_fmtLocal(_startLocal)),
                      trailing: const Icon(Icons.edit_calendar_rounded),
                      onTap: _saving
                          ? null
                          : () async {
                        final picked = await _pickDateTime(initial: _startLocal);
                        if (!mounted || picked == null) return;

                        setState(() {
                          _startLocal = picked;
                          final end = _endLocal;
                          if (end == null || !end.isAfter(picked)) {
                            _endLocal = picked.add(const Duration(days: 7));
                          }
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.stop_rounded),
                      title: const Text('Ende'),
                      subtitle: Text(_fmtLocal(_endLocal)),
                      trailing: const Icon(Icons.edit_calendar_rounded),
                      onTap: _saving
                          ? null
                          : () async {
                        final start = _startLocal;
                        final picked = await _pickDateTime(
                          initial: _endLocal ?? start?.add(const Duration(days: 7)),
                          firstDate: start != null ? DateTime(start.year - 1) : null,
                        );
                        if (!mounted || picked == null) return;
                        setState(() => _endLocal = picked);
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.check_rounded),
                        label: Text(_saving ? 'Speichern…' : 'Speichern'),
                      ),
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
