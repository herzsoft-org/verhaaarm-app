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

  bool _isAttendanceSystemTitle(String title) {
    final t = title.trim().toLowerCase();
    return t == 'absent' || t == 'late';
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
      final periods = await widget.api.listPeriods();

      // Backend change: supports /fine-catalog?forCreation=true
      // This should exclude system attendance items (absent/late) from the result.
      final catalog = await widget.api.listFineCatalog(active: true, forCreation: true);

      if (!mounted) return;

      // Extra safety: filter them out client-side too.
      final filtered = catalog.where((c) => !_isAttendanceSystemTitle(c.title)).toList();

      setState(() {
        _periods = periods;
        _catalog = filtered;
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
    final periodsSorted = [..._periods]..sort((a, b) => b.startDateLocal.compareTo(a.startDateLocal));

    final p = Format.findPeriodForFineDate(fineDate: _fineDate, periods: periodsSorted);
    if (p == null) return 'Unbekannt';
    return '${p.semester} · ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}';
  }

  // NEW: searchable catalog picker (bottom sheet)
  Future<void> _pickCatalogItem() async {
    if (_saving) return;

    final picked = await showModalBottomSheet<FineCatalogItemDto?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CatalogPickerSheet(
        title: 'Katalogeintrag suchen',
        items: _catalog,
        initial: _selectedCatalogItem,
      ),
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedCatalogItem = picked;
        _multiplier = 1;
      });
      // If the dropdown was the only missing field, revalidate.
      _formKey.currentState?.validate();
    }
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
        const SnackBar(content: Text('Bitte gültigen Betrag angeben.')),
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

    // Extra safety: never allow selecting system attendance items from UI.
    if (_useCatalog && _selectedCatalogItem != null && _isAttendanceSystemTitle(_selectedCatalogItem!.title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dieser Katalogeintrag wird automatisch durch Anwesenheit vergeben.')),
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
                  // Date picker: icon left + looks obviously clickable
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _saving ? null : _pickFineDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Datum',
                                    style: Theme.of(context).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    Format.dateOnlyShort(_fineDate),
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Conventsperiode: ${_periodLabelForFineDate()}',
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
                          showSelectedIcon: false, // <- fixes the extra width from the ✓
                          style: const ButtonStyle(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('Katalog', overflow: TextOverflow.ellipsis),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text('Custom', overflow: TextOverflow.ellipsis),
                            ),
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
                    // FIX: revalidate fields automatically as the user interacts/edits
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      children: [
                        if (_useCatalog) ...[
                          // NEW: searchable picker field (instead of DropdownButtonFormField)
                          _CatalogPickerField(
                            enabled: !_saving,
                            value: _selectedCatalogItem,
                            onTap: _pickCatalogItem,
                            validator: (_) {
                              if (_useCatalog && _selectedCatalogItem == null) {
                                return 'Bitte Beihängung auswählen.';
                              }
                              final v = _selectedCatalogItem;
                              if (v != null && _isAttendanceSystemTitle(v.title)) {
                                return 'Dieser Eintrag ist ein Systemeintrag (Anwesenheit).';
                              }
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
                          // FIX: ensure the error disappears immediately once text is entered
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return 'Bitte Grund angeben';
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
                              if (def < 0) return 'Bitte gültigen Betrag angeben.';
                              return null;
                            }
                            final cents = Format.eurTextToCents(v ?? '');
                            if (cents == null) return 'Bitte gültigen Betrag angeben.';
                            if (cents < 0) return 'Bitte gültigen Betrag angeben.';
                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'Mehrfach beihängen?',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        const SizedBox(height: 6),

                        _MultiplierRow(
                          value: _multiplier,
                          onMinus: _saving
                              ? null
                              : () => setState(() => _multiplier = _clampMultiplier(_multiplier - 1)),
                          onPlus: _saving
                              ? null
                              : () => setState(() => _multiplier = _clampMultiplier(_multiplier + 1)),
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
                    : 'Hinweis: Vorschläge müssen erst von dem Sprecher oder Schmuckwart angenommen werden.',
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _CatalogPickerField extends FormField<FineCatalogItemDto?> {
  _CatalogPickerField({
    required bool enabled,
    required FineCatalogItemDto? value,
    required VoidCallback onTap,
    String? Function(FineCatalogItemDto?)? validator,
  }) : super(
    initialValue: value,
    validator: validator,
    builder: (state) {
      final theme = Theme.of(state.context);
      final text = value?.title ?? 'Beihängungsgrund';

      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Katalogeintrag',
            prefixIcon: const Icon(Icons.search_rounded),
            errorText: state.errorText,
            enabled: enabled,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: value == null
                      ? theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                      : theme.textTheme.bodyLarge,
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CatalogPickerSheet extends StatefulWidget {
  final String title;
  final List<FineCatalogItemDto> items;
  final FineCatalogItemDto? initial;

  const _CatalogPickerSheet({
    required this.title,
    required this.items,
    required this.initial,
  });

  @override
  State<_CatalogPickerSheet> createState() => _CatalogPickerSheetState();
}

class _CatalogPickerSheetState extends State<_CatalogPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.items
        : widget.items.where((c) => c.title.toLowerCase().contains(query)).toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Schließen',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Suchen…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                      tooltip: 'Leeren',
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Keine Treffer.'))
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final c = filtered[i];
                    final selected = widget.initial?.id == c.id;

                    return Material(
                      color: selected
                          ? Theme.of(context).colorScheme.surfaceContainerHighest
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
            const SizedBox(height: 8),
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
