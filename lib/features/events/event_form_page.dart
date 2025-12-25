import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class EventFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String? eventId;

  const EventFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.eventId,
  });

  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  bool _loading = true;
  bool _saving = false;

  List<ConventPeriodDto> _periods = const [];
  String? _periodId;

  final _title = TextEditingController();
  DateTime? _startsAtLocal;
  bool _mandatory = false;

  EventDto? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!Roles.canCreateEvent(roles)) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final periods = await widget.api.listPeriods();
      periods.sort((a, b) => b.startAt.compareTo(a.startAt)); // newest first

      EventDto? existing;
      if (widget.eventId != null) {
        existing = await widget.api.getEvent(widget.eventId!);
      } else {
        // default period: active
        final active = await widget.api.getActivePeriod();
        _periodId = active.id;
      }

      if (existing != null) {
        _existing = existing;
        _periodId = existing.periodId;
        _title.text = existing.title;
        _mandatory = existing.mandatory;
        _startsAtLocal = DateTime.parse(existing.startsAt).toLocal();
      }

      if (!mounted) return;
      setState(() => _periods = periods);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Termin laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = _startsAtLocal ?? now.add(const Duration(hours: 2));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    if (!mounted) return;
    setState(() {
      _startsAtLocal = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String? _validate() {
    if (_periodId == null || _periodId!.isEmpty) return 'Bitte Conventsperiode wählen.';
    if (_title.text.trim().isEmpty) return 'Bitte Titel eingeben.';
    if (_startsAtLocal == null) return 'Bitte Datum/Uhrzeit wählen.';
    if (_startsAtLocal!.isBefore(DateTime.now())) return 'Termin darf nicht in der Vergangenheit liegen.';
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    setState(() => _saving = true);
    try {
      final isoUtc = _startsAtLocal!.toUtc().toIso8601String();

      if (_existing == null) {
        await widget.api.createEvent(
          CreateEventRequest(
            periodId: _periodId!,
            title: _title.text.trim(),
            startsAt: isoUtc,
            mandatory: _mandatory,
          ),
        );
      } else {
        await widget.api.updateEvent(
          _existing!.id,
          UpdateEventRequest(
            periodId: _periodId,
            title: _title.text.trim(),
            startsAt: isoUtc,
            mandatory: _mandatory,
          ),
        );
      }

      if (!mounted) return;
      GoRouter.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Termin löschen?'),
        content: const Text('Der Termin wird soft-deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await widget.api.deleteEvent(existing.id);
      if (!mounted) return;
      GoRouter.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final allowed = Roles.canCreateEvent(roles);

    final pSelected = _periods.where((p) => p.id == _periodId).cast<ConventPeriodDto?>().firstOrNull;

    final startsAtText = (_startsAtLocal == null)
        ? 'Nicht gesetzt'
        : Format.dateTimeShort(_startsAtLocal!.toUtc().toIso8601String());

    return AppScaffold(
      title: widget.eventId == null ? 'Neuer Termin' : 'Termin bearbeiten',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading || _saving ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (!allowed)
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Keine Berechtigung (nur Senior/Housekeeping/Admin).'),
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Details', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    initialValue: _periodId,
                    decoration: const InputDecoration(
                      labelText: 'Conventsperiode',
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                    ),
                    items: _periods
                        .map(
                          (p) => DropdownMenuItem<String>(
                        value: p.id,
                        child: Text('${p.semester} · ${Format.dateShort(p.startAt)} – ${Format.dateShort(p.endAt)}'),
                      ),
                    )
                        .toList(),
                    onChanged: _saving ? null : (v) => setState(() => _periodId = v),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _title,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Titel',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),

                  const SizedBox(height: 12),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Datum / Uhrzeit'),
                    subtitle: Text(startsAtText),
                    trailing: FilledButton.tonal(
                      onPressed: _saving ? null : _pickDateTime,
                      child: const Text('Wählen'),
                    ),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mandatory,
                    onChanged: _saving ? null : (v) => setState(() => _mandatory = v),
                    title: const Text('Pflichttermin'),
                    subtitle: Text(
                      'Owner: ${Roles.isHousekeeping(roles) ? 'HOUSEKEEPING' : 'SENIOR'}'
                          '${pSelected?.locked == true ? ' · Hinweis: Periode locked' : ''}',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(_existing == null ? 'Erstellen' : 'Speichern'),
                ),
              ),
              const SizedBox(width: 12),
              if (_existing != null)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Löschen'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
