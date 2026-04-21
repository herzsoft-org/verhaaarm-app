import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../fines/member_picker_sheet.dart';

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

  final _title = TextEditingController();
  DateTime? _startsAtLocal;
  bool _mandatory = false;
  EventKind _eventKind = EventKind.main;

  EventDto? _existing;

  List<AttendanceDto> _attendance = const [];
  Map<String, UserPickerDto> _userById = const {};

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
      periods.sort((a, b) => b.startAt.compareTo(a.startAt));

      final users = await widget.api.pickerUsers();
      final userById = {for (final u in users) u.id: u};

      EventDto? existing;
      List<AttendanceDto> attendance = const [];

      if (widget.eventId != null) {
        existing = await widget.api.getEvent(widget.eventId!);
        attendance = await widget.api.listAttendance(existing.id);

        _existing = existing;
        _title.text = existing.title;
        _mandatory = existing.mandatory;
        _eventKind = existing.eventKind;
        _startsAtLocal = DateTime.parse(existing.startsAt).toLocal();
      } else {
        final now = DateTime.now();
        _startsAtLocal ??= now.add(const Duration(hours: 2));
        _eventKind = EventKind.main;
      }

      if (!mounted) return;
      setState(() {
        _periods = periods;
        _userById = userById;
        _attendance = attendance;
      });
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

    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    if (!mounted) return;
    setState(() {
      _startsAtLocal =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Bitte Titel eingeben.';
    if (_startsAtLocal == null) return 'Bitte Datum/Uhrzeit wählen.';
    if (_startsAtLocal!.isBefore(DateTime.now())) {
      return 'Termin darf nicht in der Vergangenheit liegen.';
    }
    return null;
  }

  ConventPeriodDto? _derivedPeriodForLocal(DateTime? local) {
    if (local == null) return null;
    final dt = local;
    for (final p in _periods) {
      final start = p.startDateLocal;
      final end = p.endDateLocal;
      if (!dt.isBefore(start) && !dt.isAfter(end)) return p;
    }
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
            title: _title.text.trim(),
            startsAt: isoUtc,
            mandatory: _mandatory,
            eventKind: _eventKind,
          ),
        );
      } else {
        await widget.api.updateEvent(
          _existing!.id,
          UpdateEventRequest(
            title: _title.text.trim(),
            startsAt: isoUtc,
            mandatory: _mandatory,
            eventKind: _eventKind,
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

  String _userLabel(String id) {
    final u = _userById[id];
    if (u == null) return id;
    return u.displayName;
  }

  Future<String?> _pickOneMember() async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: MemberPickerSheet(
          api: widget.api,
          initialSelectedIds: const <String>{},
        ),
      ),
    );
    if (res == null || res.isEmpty) return null;
    return res.first;
  }

  Future<int?> _askLateMinutes() async {
    final ctrl = TextEditingController(text: '5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zu spät (Minuten)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minuten',
            hintText: 'z.B. 5',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    final v = int.tryParse(ctrl.text.trim());
    if (v == null || v < 0) return null;
    return v;
  }

  Future<void> _addAttendance(AttendanceStatus status) async {
    final e = _existing;
    if (e == null) return;

    final userId = await _pickOneMember();
    if (userId == null) return;

    int? lateMinutes;
    if (status == AttendanceStatus.late) {
      lateMinutes = await _askLateMinutes();
      if (lateMinutes == null) return;
    }

    setState(() => _saving = true);
    try {
      await widget.api.upsertAttendance(
        e.id,
        UpsertAttendanceRequest(
          userId: userId,
          status: status,
          lateMinutes: lateMinutes,
        ),
      );
      final updated = await widget.api.listAttendance(e.id);

      if (!mounted) return;
      setState(() => _attendance = updated);
    } catch (ex) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anwesenheit speichern fehlgeschlagen: $ex')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeAttendance(String userId) async {
    final e = _existing;
    if (e == null) return;

    setState(() => _saving = true);
    try {
      await widget.api.deleteAttendance(e.id, userId);
      final updated = await widget.api.listAttendance(e.id);

      if (!mounted) return;
      setState(() => _attendance = updated);
    } catch (ex) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anwesenheit löschen fehlgeschlagen: $ex')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final allowed = Roles.canCreateEvent(roles);

    final startsAtText = (_startsAtLocal == null)
        ? 'Nicht gesetzt'
        : Format.dateTimeShort(_startsAtLocal!.toUtc().toIso8601String());

    final derived = _derivedPeriodForLocal(_startsAtLocal);
    final derivedText = (derived == null)
        ? 'Unbekannt'
        : '${derived.semester} · ${Format.dateShort(derived.startAt)} – ${Format.dateShort(derived.endAt)}'
        '${derived.locked ? ' · locked' : ''}'
        '${derived.active ? ' · aktiv' : ''}';

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
          child: Text(
              'Keine Berechtigung (nur Senior/Housekeeping/Admin).'),
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
                  Text('Details',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                    const Icon(Icons.calendar_month_rounded),
                    title: const Text('Conventsperiode (automatisch)'),
                    subtitle: Text(derivedText),
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
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Veranstaltungstyp',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<EventKind>(
                        segments: const [
                          ButtonSegment<EventKind>(
                            value: EventKind.main,
                            label: Text('Sempro'),
                            icon: Icon(Icons.event_rounded),
                          ),
                          ButtonSegment<EventKind>(
                            value: EventKind.secondary,
                            label: Text('Wochenplan (Aufbau, Aufräumen...)'),
                            icon: Icon(Icons.event_note_rounded),
                          ),
                        ],
                        selected: {_eventKind},
                        onSelectionChanged: _saving
                            ? null
                            : (selection) {
                          setState(() => _eventKind = selection.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _eventKind.labelDe,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mandatory,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _mandatory = v),
                    title: const Text('Pflichttermin'),
                  ),
                ],
              ),
            ),
          ),
          if (_existing != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Anwesenheit',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _saving
                                  ? null
                                  : () => _addAttendance(AttendanceStatus.absent),
                              icon: const Icon(Icons.person_off_rounded),
                              label: const Text('Bbr. abwesend?'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _saving
                                  ? null
                                  : () => _addAttendance(AttendanceStatus.late),
                              icon: const Icon(Icons.timer_rounded),
                              label: const Text('Bbr. zu spät?'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_attendance.isEmpty)
                      Text(
                        'Keine Bbr. abwesend oder zu spät :)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (final a in _attendance)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          elevation: 0,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: ListTile(
                            leading: Icon(
                              a.status == AttendanceStatus.absent
                                  ? Icons.person_off_rounded
                                  : Icons.timer_rounded,
                            ),
                            title: Text(_userLabel(a.userId)),
                            subtitle: Text(
                              a.status == AttendanceStatus.absent
                                  ? 'ABSENT'
                                  : 'LATE · ${a.lateMinutes ?? 0} min',
                            ),
                            trailing: IconButton(
                              tooltip: 'Entfernen',
                              onPressed: _saving
                                  ? null
                                  : () => _removeAttendance(a.userId),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(_existing == null
                      ? 'Erstellen'
                      : 'Speichern'),
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