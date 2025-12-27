// lib/features/fines/fine_form_page.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import 'member_picker_sheet.dart';
import 'fine_photos_dialog.dart';
import '../../auth/auth_store.dart';

enum FineFormMode { official, suggestion }

class FineFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final FineFormMode mode;

  const FineFormPage({
    super.key,
    required this.api,
    required this.authStore,
    required this.mode,
  });

  @override
  State<FineFormPage> createState() => _FineFormPageState();
}


class _FineFormPageState extends State<FineFormPage> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  ConventPeriodDto? _activePeriod;
  List<ConventPeriodDto> _periods = const [];
  List<FineCatalogItemDto> _catalog = const [];

  bool _useCatalog = true;
  FineCatalogItemDto? _selectedCatalogItem;

  int _multiplier = 1;

  // IMPORTANT: reason is required for BOTH catalog + custom
  final _reason = TextEditingController();

  // custom amount input (EUR)
  final _amount = TextEditingController();

  Set<String> _targetUserIds = <String>{};

  // fineDate (YYYY-MM-DD)
  String _fineDate = _todayIsoDate();

  static String _todayIsoDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final period = await widget.api.getActivePeriod();
      final periods = await widget.api.listPeriods();
      final catalog = await widget.api.listFineCatalog(active: true);

      if (!mounted) return;

      setState(() {
        _activePeriod = period;
        _periods = periods;
        _catalog = catalog;
        _selectedCatalogItem = null; // placeholder default
        _multiplier = 1;

        // default fineDate: today (or keep if already set)
        if (_fineDate.trim().isEmpty) _fineDate = _todayIsoDate();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Initialisierung fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _askAddImagesAfterCreate(String fineId) async {
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotos hinzufügen?'),
        content: const Text('Möchtest du jetzt Fotos zu dieser Beihängung hochladen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Nein')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Ja')),
        ],
      ),
    );

    if (add == true && mounted) {
      await FinePhotosDialog.openAdd(
        context: context,
        api: widget.api,
        authStore: widget.authStore,
        fineId: fineId,
        maxPhotos: 5,
        currentCount: 0,
      );
    }
  }


  String _toEurText(int cents) {
    final s = Format.centsToEur(cents);
    return s.replaceAll('€', '').trim();
  }

  int _clampMultiplier(int v) => v < 1 ? 1 : (v > 99 ? 99 : v);

  int? _baseAmountCents() {
    if (_useCatalog) {
      return _selectedCatalogItem?.defaultAmountCents;
    }
    return Format.eurTextToCents(_amount.text);
  }

  int? _totalAmountCents() {
    final base = _baseAmountCents();
    if (base == null) return null;
    return base * _multiplier;
  }

  String _totalAmountLabel() {
    final total = _totalAmountCents();
    if (total == null) return '—';
    return _toEurText(total);
  }

  Future<void> _pickMembers() async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: MemberPickerSheet(
          api: widget.api,
          initialSelectedIds: _targetUserIds,
        ),
      ),
    );

    if (res != null && mounted) {
      setState(() => _targetUserIds = res);
    }
  }

  Future<void> _pickFineDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_fineDate) ?? DateTime(now.year, now.month, now.day);

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;

    final picked = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    setState(() => _fineDate = picked);
  }

  String _periodLabelForFineDate() {
    final periodsSorted = [..._periods]
      ..sort((a, b) => Format.parseIsoToLocal(b.startAt).compareTo(Format.parseIsoToLocal(a.startAt)));

    final p = Format.findPeriodForFineDate(fineDate: _fineDate, periods: periodsSorted);
    if (p == null) return 'Unbekannt';
    return '${p.semester} · ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}';
  }

  Future<void> _submit() async {
    if (_saving) return;

    if (_targetUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens 1 Bbr. auswählen.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final totalCents = _totalAmountCents();
    if (totalCents == null || totalCents < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ungültiger Betrag.')),
      );
      return;
    }

    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grund fehlt.')),
      );
      return;
    }

    // fineDate sanity
    final fd = _fineDate.trim();
    if (fd.isEmpty || DateTime.tryParse(fd) == null || fd.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ungültiges Datum.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      if (widget.mode == FineFormMode.official) {
        final req = CreateFineRequest(
          fineDate: fd,
          targetUserIds: _targetUserIds.toList(),
          catalogItemId: _useCatalog ? _selectedCatalogItem?.id : null,
          reason: reason,
          amountCents: totalCents,
        );

        final fine = await widget.api.createFine(req);

        if (!mounted) return;

        // Ask before navigating away
        await _askAddImagesAfterCreate(fine.id);
        if (!mounted) return;

        context.pushReplacement('/fines/${fine.id}');

      } else {
        final req = CreateFineSuggestionRequest(
          fineDate: fd,
          targetUserIds: _targetUserIds.toList(),
          catalogItemId: _useCatalog ? _selectedCatalogItem?.id : null,
          reason: reason,
          amountCents: totalCents,
        );

        await widget.api.createSuggestion(req);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vorschlag erstellt. Fotos können erst nach Annahme hinzugefügt werden.')),
        );
        context.go('/home');
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (!mounted) return;

      if (code == 403 && widget.mode == FineFormMode.official) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Berechtigung zum Hinzufügen. Bitte Vorschlag nutzen.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
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
    final title = widget.mode == FineFormMode.official ? 'Beihängen' : 'Beihängung vorschlagen';

    return AppScaffold(
      title: title,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Datum', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _saving ? null : _pickFineDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(child: Text(Format.dateOnlyShort(_fineDate))),
                          const Icon(Icons.calendar_month_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Zuordnung (aus Datum): ${_periodLabelForFineDate()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Aktive Conventsperiode (Info): ${_activePeriod == null ? '—' : _activePeriod!.semester}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('Katalog')),
                            ButtonSegment(value: false, label: Text('Custom')),
                          ],
                          selected: {_useCatalog},
                          onSelectionChanged: (s) {
                            setState(() {
                              _useCatalog = s.first;
                              _multiplier = 1;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_useCatalog) ...[
                          DropdownButtonFormField<FineCatalogItemDto>(
                            initialValue: _selectedCatalogItem,
                            items: [
                              const DropdownMenuItem<FineCatalogItemDto>(
                                value: null,
                                child: Text('Beihängung auswählen'),
                              ),
                              ..._catalog.map(
                                    (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c.title),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _selectedCatalogItem = v;
                                _multiplier = 1;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Katalogeintrag',
                              prefixIcon: Icon(Icons.list_rounded),
                            ),
                            validator: (v) {
                              if (_useCatalog && v == null) return 'Bitte Beihängung auswählen.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        // IMPORTANT: reason always required (catalog + custom)
                        TextFormField(
                          controller: _reason,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Grund',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return 'Grund fehlt.';
                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // amount:
                        // - catalog: not editable (uses defaultAmountCents)
                        // - custom: editable EUR
                        TextFormField(
                          controller: _amount,
                          enabled: !_useCatalog && !_saving,
                          readOnly: _useCatalog,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _useCatalog ? 'Betrag (aus Katalog)' : 'Betrag (z.B. 1,50)',
                            prefixIcon: const Icon(Icons.euro_rounded),
                            hintText: _useCatalog ? '—' : 'z.B. 2,50',
                          ),
                          validator: (v) {
                            if (_useCatalog) {
                              final def = _selectedCatalogItem?.defaultAmountCents;
                              if (def == null) return 'Katalogbetrag fehlt (Default Betrag).';
                              if (def < 0) return 'Ungültiger Betrag.';
                              return null;
                            }
                            final cents = Format.eurTextToCents(v ?? '');
                            if (cents == null) return 'Ungültiger Betrag.';
                            if (cents < 0) return 'Ungültiger Betrag.';
                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        _MultiplierRow(
                          value: _multiplier,
                          onMinus: _saving ? null : () => setState(() => _multiplier = _clampMultiplier(_multiplier - 1)),
                          onPlus: _saving ? null : () => setState(() => _multiplier = _clampMultiplier(_multiplier + 1)),
                          totalLabel: _totalAmountLabel(),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: _saving ? null : _pickMembers,
                            icon: const Icon(Icons.group_add_rounded),
                            label: Text('Bbr. auswählen (${_targetUserIds.length})'),
                          ),
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
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.mode == FineFormMode.official
                    ? 'Hinweis: Offizielle Beihängungen nur mit Berechtigung.'
                    : 'Hinweis: Vorschläge beeinflussen den Saldo nicht direkt.',
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _MultiplierRow extends StatelessWidget {
  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final String totalLabel;

  const _MultiplierRow({
    required this.value,
    required this.onMinus,
    required this.onPlus,
    required this.totalLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            const Icon(Icons.close_rounded),
            const SizedBox(width: 8),
            Text('x$value', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onMinus,
              icon: const Icon(Icons.remove_circle_outline_rounded),
              tooltip: '-',
            ),
            IconButton(
              onPressed: onPlus,
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: '+',
            ),
            const Spacer(),
            Text('Gesamt: $totalLabel', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
