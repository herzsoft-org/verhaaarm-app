import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/csv_export/csv_export.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class OfficePage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const OfficePage({super.key, required this.api, required this.authStore});

  @override
  State<OfficePage> createState() => _OfficePageState();
}

class _OfficePageState extends State<OfficePage> {
  static const String _statusOpenSuggestion = 'PENDING';

  bool _csvBusy = false;
  int _openSuggestions = 0;

  @override
  void initState() {
    super.initState();
    _loadOpenSuggestionsCount();
  }

  Future<void> _loadOpenSuggestionsCount() async {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    if (!Roles.canAcceptFineSuggestions(roles)) return;

    try {
      final suggestions = await widget.api.listSuggestions(
        status: _statusOpenSuggestion,
      );

      if (!mounted) return;
      setState(() {
        _openSuggestions = suggestions.length;
      });
    } catch (_) {
      // Silent: the office page should still be usable if the badge count fails.
    }
  }

  Widget _countBadge(BuildContext context, int n) {
    if (n <= 0) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$n',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);

    if (!Roles.canAccessOffice(roles)) {
      return const AppScaffold(
        title: 'Amtsausführung',
        body: Center(child: Text('Kein Zugriff.')),
      );
    }

    final canUsers = Roles.canManageUsers(roles);
    final canCatalog = Roles.canManageCatalog(roles);
    final canPeriods = Roles.canManagePeriods(roles);
    final canAcceptSuggestions = Roles.canAcceptFineSuggestions(roles);
    final canTasks = Roles.canManageTasks(roles);
    final isAdmin = roles.contains(AppRole.admin);

    return AppScaffold(
      title: 'Amtsausführung',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (canTasks) ...[
            _Section(
              title: 'Arbeitsaufträge',
              children: [
                ListTile(
                  leading: const Icon(Icons.assignment_rounded),
                  title: const Text('Arbeitsaufträge verwalten'),
                  subtitle: const Text('Alle Nutzer · bearbeiten · löschen'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/office/tasks'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _Section(
            title: 'Beihängungen',
            children: [
              ListTile(
                leading: const Icon(Icons.list_alt_rounded),
                title: const Text('Alle Beihängungen'),
                subtitle: const Text(
                  'Alle Nutzer, alle Conventsperioden (nach Backend-Rechten)',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/fines'),
              ),
              if (canAcceptSuggestions)
                ListTile(
                  leading: const Icon(Icons.inbox_rounded),
                  title: const Text('Vorgeschlagene Beihängungen'),
                  subtitle: const Text('Ansehen, akzeptieren oder ablehnen'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _countBadge(context, _openSuggestions),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () async {
                    await context.push('/office/fine-suggestions');
                    if (!mounted) return;
                    await _loadOpenSuggestionsCount();
                  },
                ),
              if (canCatalog)
                ListTile(
                  leading: const Icon(Icons.rule_rounded),
                  title: const Text('Beihängungskatalog verwalten'),
                  subtitle: const Text('Gründe + Default Beträge'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/office/catalog'),
                ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('CSV Export'),
                subtitle: Text(
                  _csvBusy
                      ? 'Conventsperioden werden geladen / Export läuft ...'
                      : 'Semester oder einzelne Conventsperiode exportieren',
                ),
                trailing: _csvBusy
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _csvBusy ? null : _startCsvExportFlow,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (canPeriods)
            _Section(
              title: 'Semester & Conventsperioden',
              children: [
                ListTile(
                  leading: const Icon(Icons.date_range_rounded),
                  title: const Text('Semester / Conventsperioden verwalten'),
                  subtitle: const Text('Erstellen, ändern, aktivieren, locken'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/office/periods'),
                ),
              ],
            ),
          if (canPeriods) const SizedBox(height: 12),
          if (canUsers)
            _Section(
              title: 'Nutzerverwaltung',
              children: [
                ListTile(
                  leading: const Icon(Icons.people_rounded),
                  title: const Text('Nutzer verwalten'),
                  subtitle: const Text(
                    'Erstellen, Rollen, deaktivieren, Passwort setzen',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/office/users'),
                ),
              ],
            ),
          if (canUsers) const SizedBox(height: 12),
          if (isAdmin)
            _Section(
              title: 'Sessions',
              children: [
                ListTile(
                  leading: const Icon(Icons.analytics_rounded),
                  title: const Text('Session-Statistik'),
                  subtitle: const Text(
                    'Aktive Sessions nach Zeitraum, App-Typ und Browser',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/office/session-stats'),
                ),
              ],
            ),
          if (isAdmin) const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _startCsvExportFlow() async {
    if (_csvBusy) return;

    setState(() {
      _csvBusy = true;
    });

    List<ConventPeriodDto> periods;
    ConventPeriodDto? activePeriod;

    try {
      periods = await widget.api.listPeriods();

      try {
        activePeriod = await widget.api.getActivePeriod();
      } catch (_) {
        for (final p in periods) {
          if (p.active) {
            activePeriod = p;
            break;
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _csvBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conventsperioden konnten nicht geladen werden: $e'),
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _csvBusy = false;
    });

    if (periods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Conventsperioden vorhanden.')),
      );
      return;
    }

    final result = await _showCsvExportDialog(
      periods: periods,
      activePeriod: activePeriod,
    );

    if (result == null) return;

    switch (result.scope) {
      case ExportScope.period:
        await _exportSinglePeriod(
          periodId: result.periodId!,
          periods: periods,
        );
        break;
      case ExportScope.semester:
        await _exportSemester(
          semester: result.semester!,
          periods: periods,
        );
        break;
    }
  }

  Future<_ExportDialogResult?> _showCsvExportDialog({
    required List<ConventPeriodDto> periods,
    required ConventPeriodDto? activePeriod,
  }) async {
    final grouped = _groupBySemester(periods);
    final semesters = grouped.keys.toList();

    String selectedSemester;
    String? selectedPeriodId;

    if (activePeriod != null) {
      selectedSemester = activePeriod.semester;
      selectedPeriodId = activePeriod.id;
    } else {
      selectedSemester = semesters.first;
      final periodsInSemester = grouped[selectedSemester]!;
      selectedPeriodId =
      periodsInSemester.isNotEmpty ? periodsInSemester.first.id : null;
    }

    ExportScope scope = ExportScope.period;

    return showDialog<_ExportDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final periodsInSelectedSemester =
                grouped[selectedSemester] ?? const <ConventPeriodDto>[];

            if (scope == ExportScope.period) {
              final hasSelectedPeriod = periodsInSelectedSemester.any(
                    (p) => p.id == selectedPeriodId,
              );
              if (!hasSelectedPeriod) {
                selectedPeriodId = periodsInSelectedSemester.isNotEmpty
                    ? periodsInSelectedSemester.first.id
                    : null;
              }
            }

            final canSubmit = switch (scope) {
              ExportScope.period => selectedPeriodId != null,
              ExportScope.semester => selectedSemester.isNotEmpty,
            };

            return AlertDialog(
              title: const Text('CSV Export'),
              content: SingleChildScrollView(
                child: RadioGroup<ExportScope>(
                  groupValue: scope,
                  onChanged: (value) {
                    setDialogState(() {
                      scope = value!;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadioListTile<ExportScope>(
                        value: ExportScope.period,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Conventsperiode exportieren'),
                        subtitle: const Text('Standard: aktuelle Periode'),
                      ),
                      if (scope == ExportScope.period) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedSemester,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Semester',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final semester in semesters)
                              DropdownMenuItem<String>(
                                value: semester,
                                child: Text(semester),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              selectedSemester = value;
                              final updatedPeriods =
                                  grouped[selectedSemester] ??
                                      const <ConventPeriodDto>[];
                              selectedPeriodId = updatedPeriods.isNotEmpty
                                  ? updatedPeriods.first.id
                                  : null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedPeriodId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Conventsperiode',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final period in periodsInSelectedSemester)
                              DropdownMenuItem<String>(
                                value: period.id,
                                child: Text(_periodLabel(period)),
                              ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedPeriodId = value;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      RadioListTile<ExportScope>(
                        value: ExportScope.semester,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Semester exportieren'),
                        subtitle: const Text(
                          'Alle Perioden des ausgewählten Semesters zusammenführen',
                        ),
                      ),
                      if (scope == ExportScope.semester) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedSemester,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Semester',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final semester in semesters)
                              DropdownMenuItem<String>(
                                value: semester,
                                child: Text(semester),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              selectedSemester = value;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton.icon(
                  onPressed: canSubmit
                      ? () {
                    Navigator.of(dialogContext).pop(
                      _ExportDialogResult(
                        scope: scope,
                        semester: scope == ExportScope.semester
                            ? selectedSemester
                            : null,
                        periodId: scope == ExportScope.period
                            ? selectedPeriodId
                            : null,
                      ),
                    );
                  }
                      : null,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Exportieren'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportSinglePeriod({
    required String periodId,
    required List<ConventPeriodDto> periods,
  }) async {
    if (_csvBusy) return;

    setState(() {
      _csvBusy = true;
    });

    try {
      final selectedPeriod = periods.firstWhere((p) => p.id == periodId);

      final r = await widget.api.exportFinesCsv(periodId: periodId);
      final data = r.data;

      if (data is! List<int>) {
        throw Exception('CSV Export: unerwartetes Response-Format');
      }

      final ts = _safeTimestamp();
      final filename =
          'verhaarm-fines-${_safeName(selectedPeriod.semester)}-${_safeName(_periodRangeLabel(selectedPeriod))}-$ts.csv';

      await saveCsvBytes(
        bytes: data,
        filename: filename,
        shareText: 'Verhåårm – Beihängungen Export',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV Export für ${_periodLabel(selectedPeriod)} bereit.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV Export fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _csvBusy = false;
        });
      }
    }
  }

  Future<void> _exportSemester({
    required String semester,
    required List<ConventPeriodDto> periods,
  }) async {
    if (_csvBusy) return;

    setState(() {
      _csvBusy = true;
    });

    try {
      final periodsInSemester = periods.where((p) => p.semester == semester).toList()
        ..sort(_comparePeriodsAsc);

      if (periodsInSemester.isEmpty) {
        throw Exception('Keine Conventsperioden für das Semester gefunden');
      }

      final mergedLines = <String>[];
      var headerWritten = false;

      for (final period in periodsInSemester) {
        final r = await widget.api.exportFinesCsv(periodId: period.id);
        final data = r.data;

        if (data is! List<int>) {
          throw Exception(
            'CSV Export für ${_periodLabel(period)} hat kein Byte-Format geliefert',
          );
        }

        final csvText = utf8
            .decode(data, allowMalformed: true)
            .replaceAll('\r\n', '\n')
            .trim();
        if (csvText.isEmpty) {
          continue;
        }

        final lines = csvText
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        if (lines.isEmpty) {
          continue;
        }

        if (!headerWritten) {
          mergedLines.addAll(lines);
          headerWritten = true;
        } else if (lines.length > 1) {
          mergedLines.addAll(lines.skip(1));
        }
      }

      if (mergedLines.isEmpty) {
        throw Exception('Keine CSV-Daten für das Semester vorhanden');
      }

      final mergedCsv = '${mergedLines.join('\n')}\n';
      final bytes = utf8.encode(mergedCsv);

      final ts = _safeTimestamp();
      final filename = 'verhaarm-fines-${_safeName(semester)}-gesamt-$ts.csv';

      await saveCsvBytes(
        bytes: bytes,
        filename: filename,
        shareText: 'Verhåårm – Beihängungen Export ($semester)',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV Export für $semester bereit.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV Export fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _csvBusy = false;
        });
      }
    }
  }

  Map<String, List<ConventPeriodDto>> _groupBySemester(
      List<ConventPeriodDto> periods,
      ) {
    final sorted = [...periods]..sort(_comparePeriodsDesc);
    final map = <String, List<ConventPeriodDto>>{};

    for (final period in sorted) {
      map.putIfAbsent(period.semester, () => <ConventPeriodDto>[]).add(period);
    }

    return map;
  }

  int _comparePeriodsDesc(ConventPeriodDto a, ConventPeriodDto b) {
    final aStart = _dateOnly(a.startAt);
    final bStart = _dateOnly(b.startAt);
    return bStart.compareTo(aStart);
  }

  int _comparePeriodsAsc(ConventPeriodDto a, ConventPeriodDto b) {
    final aStart = _dateOnly(a.startAt);
    final bStart = _dateOnly(b.startAt);
    return aStart.compareTo(bStart);
  }

  DateTime _dateOnly(dynamic value) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }

    return DateTime.parse(value.toString());
  }

  String _periodLabel(ConventPeriodDto p) {
    final base = '${p.semester} · ${_periodRangeLabel(p)}';

    if (p.active) {
      return '$base · aktuell';
    }
    if (p.locked) {
      return '$base · gesperrt';
    }
    return base;
  }

  String _periodRangeLabel(ConventPeriodDto p) {
    return '${_formatDate(p.startAt)} bis ${_formatDate(p.endAt)}';
  }

  String _formatDate(dynamic value) {
    final dt = _dateOnly(value);
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    return '$dd.$mm.$yyyy';
  }

  String _safeTimestamp() {
    return DateTime.now().toIso8601String().replaceAll(':', '-');
  }

  String _safeName(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^A-Za-z0-9._\-äöüÄÖÜß]'), '');
  }
}

enum ExportScope {
  period,
  semester,
}

class _ExportDialogResult {
  final ExportScope scope;
  final String? semester;
  final String? periodId;

  const _ExportDialogResult({
    required this.scope,
    required this.semester,
    required this.periodId,
  });
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}