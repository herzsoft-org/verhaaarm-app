import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/settings/app_settings_store.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../common/member_picker_settings.dart';
import '../../models/member_status.dart';

class TaskFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  final TaskDto? initial;
  final bool isEdit;
  final bool isAdminEdit;

  const TaskFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.initial,
    required this.isEdit,
    required this.isAdminEdit,
  });

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _saving = false;

  List<UserPickerDto> _assignees = const [];

  // Normal (one-off) task
  DateTime? _dueLocal;

  // Recurring weekly task
  bool _recurringEnabled = false;
  final Set<String> _recurringWeekdays = {}; // MON..SUN
  TimeOfDay? _recurringDueTime;

  bool get _sendNotificationsOnlyToMe {
    return widget.authStore.currentRoles.contains(AppRole.admin) &&
        AppSettingsStore.I.devModeNotifyOnlyMe;
  }

  @override
  void initState() {
    super.initState();
    final i = widget.initial;

    if (i != null) {
      _titleCtrl.text = i.title;
      _descCtrl.text = i.description;
      _assignees = List<UserPickerDto>.from(i.assignees);

      _dueLocal = i.dueAt?.toLocal();

      _recurringEnabled = i.recurringEnabled;
      _recurringWeekdays.addAll(i.recurringWeekdays);

      _recurringDueTime = _parseTimeOfDay(i.recurringDueTime);
    } else {
      // No preset for either mode.
      _dueLocal = null;
      _recurringDueTime = null;
    }

    if (_recurringEnabled) {
      _dueLocal = null;
      if (_recurringWeekdays.isEmpty) {
        final wd = DateTime.now().weekday; // Mon=1..Sun=7
        _recurringWeekdays.add(_weekdayOrder()[wd - 1]);
      }
    }

    // Recompute button enabled state whenever user types.
    _titleCtrl.addListener(_recomputeCanSubmit);
    _descCtrl.addListener(_recomputeCanSubmit);

    // Also ensure initial state is reflected.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeCanSubmit());
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_recomputeCanSubmit);
    _descCtrl.removeListener(_recomputeCanSubmit);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ----------------------------
  // Enable/disable submit
  // ----------------------------

  bool _canSubmit = false;

  void _recomputeCanSubmit() {
    final titleOk = _titleCtrl.text.trim().length >= 2;
    final descOk = _descCtrl.text.trim().isNotEmpty;
    final assigneesOk = _assignees.isNotEmpty;

    final scheduleOk = _recurringEnabled
        ? (_recurringWeekdays.isNotEmpty && _recurringDueTime != null)
        : (_dueLocal != null);

    final ok = !_saving && titleOk && descOk && assigneesOk && scheduleOk;

    if (ok != _canSubmit && mounted) {
      setState(() => _canSubmit = ok);
    } else if (mounted) {
      // still refresh when _saving changes externally etc.
      // (keep minimal to avoid rebuild spam)
    }
  }

  // ----------------------------
  // Pickers
  // ----------------------------

  Future<void> _pickNormalDueAt() async {
    final now = DateTime.now();

    final base = _dueLocal ?? now;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (pickedDate == null) return;
    if (!mounted) return;

    final initialTime = _dueLocal != null
        ? TimeOfDay.fromDateTime(_dueLocal!)
        : TimeOfDay.fromDateTime(now);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return;
    if (!mounted) return;

    setState(() {
      _dueLocal = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });

    _recomputeCanSubmit();
  }

  Future<void> _pickRecurringDueTime() async {
    final initial = _recurringDueTime ?? TimeOfDay.fromDateTime(DateTime.now());
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _recurringDueTime = picked);
    _recomputeCanSubmit();
  }

  // ----------------------------
  // Helpers
  // ----------------------------

  TimeOfDay? _parseTimeOfDay(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickAssignees() async {
    final selectedIds = _assignees.map((e) => e.id).toSet();

    final result = await showModalBottomSheet<List<UserPickerDto>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AssigneePickerSheet(
        api: widget.api,
        initiallySelectedUsers: _assignees,
        initiallySelectedIds: selectedIds,
      ),
    );

    if (result == null) return;
    if (!mounted) return;
    setState(() => _assignees = List<UserPickerDto>.unmodifiable(result));
    _recomputeCanSubmit();
  }

  String _weekdayLabel(String w) {
    switch (w) {
      case 'MON':
        return 'Mo';
      case 'TUE':
        return 'Di';
      case 'WED':
        return 'Mi';
      case 'THU':
        return 'Do';
      case 'FRI':
        return 'Fr';
      case 'SAT':
        return 'Sa';
      case 'SUN':
        return 'So';
      default:
        return w;
    }
  }

  List<String> _weekdayOrder() => const [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  String _formatDueLocal(DateTime? d) {
    if (d == null) return 'Bitte wählen';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatRecurringTime(TimeOfDay? t) {
    if (t == null) return 'Bitte wählen';
    return _formatTimeOfDay(t);
  }

  void _setMode(bool recurring) {
    setState(() {
      _recurringEnabled = recurring;

      if (recurring) {
        // Switching to recurring: normal due is irrelevant.
        _dueLocal = null;

        // Do not preset time.
        // Keep weekdays if already selected; if none, pick current weekday as a helpful default selection.
        if (_recurringWeekdays.isEmpty) {
          final wd = DateTime.now().weekday; // Mon=1..Sun=7
          _recurringWeekdays.add(_weekdayOrder()[wd - 1]);
        }
      } else {
        // Switching to normal: clear recurring weekdays selection (as before),
        // and require user to pick a due date/time manually.
        _recurringWeekdays.clear();
        _recurringDueTime = null;
      }
    });

    _recomputeCanSubmit();
  }

  // ----------------------------
  // Save
  // ----------------------------

  Future<void> _save() async {
    if (_saving) return;

    // Hard guard: button should already be disabled, but keep it safe.
    if (!_canSubmit) {
      // Run validators to show field errors if needed.
      _formKey.currentState?.validate();

      if (!_recurringEnabled && _dueLocal == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte Fälligkeit (Datum/Uhrzeit) wählen.'),
          ),
        );
      } else if (_recurringEnabled && _recurringDueTime == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bitte Uhrzeit wählen.')));
      } else if (_assignees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte mindestens einen Empfänger wählen.'),
          ),
        );
      }
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final assigneeIds = _assignees.map((e) => e.id).toList(growable: false);

    final dueAt = _recurringEnabled ? null : _dueLocal;

    final recurringWeekdays = _recurringEnabled
        ? _weekdayOrder()
              .where(_recurringWeekdays.contains)
              .toList(growable: false)
        : null;

    final recurringDueTimeStr = (_recurringEnabled && _recurringDueTime != null)
        ? _formatTimeOfDay(_recurringDueTime!)
        : null;

    setState(() {
      _saving = true;
      _canSubmit = false;
    });

    TaskDto? saved;

    try {
      if (widget.isEdit) {
        final id = widget.initial!.id;
        saved = await widget.api.updateTask(
          id,
          UpdateTaskRequest(
            title: title,
            description: desc,
            assigneeUserIds: assigneeIds,
            dueAt: _recurringEnabled ? null : dueAt,
            recurringEnabled: _recurringEnabled,
            recurringWeekdays: _recurringEnabled ? recurringWeekdays : null,
            recurringDueTime: _recurringEnabled ? recurringDueTimeStr : null,
          ),
        );
      } else {
        saved = await widget.api.createTask(
          CreateTaskRequest(
            title: title,
            description: desc,
            assigneeUserIds: assigneeIds,
            dueAt: dueAt,
            recurringEnabled: _recurringEnabled ? true : false,
            recurringWeekdays: recurringWeekdays,
            recurringDueTime: recurringDueTimeStr,
            notifyOnlyMe: _sendNotificationsOnlyToMe,
          ),
        );
      }

      if (!mounted) return;
      context.pop(saved); // <-- return TaskDto instead of true
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _recomputeCanSubmit();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = widget.isEdit
        ? 'Arbeitsauftrag bearbeiten'
        : 'Arbeitsauftrag erstellen';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final showDevModeNote = !widget.isEdit && _sendNotificationsOnlyToMe;

    return AppScaffold(
      title: pageTitle,
      actions: [
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: _canSubmit ? _save : null,
        ),
      ],
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_saving) const LinearProgressIndicator(),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (showDevModeNote) ...[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Dev-Modus aktiv: Benachrichtigungen werden nur an dich gesendet.',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Titel',
                          prefixIcon: Icon(Icons.title_rounded),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Titel fehlt';
                          if (s.length < 2) return 'Titel zu kurz';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Beschreibung',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                        minLines: 3,
                        maxLines: 8,
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Beschreibung fehlt';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickAssignees,
                        child: Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(Icons.people_rounded),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _assignees.isEmpty
                                        ? 'Empfänger wählen'
                                        : 'Empfänger: ${_assignees.map((e) => e.displayName).join(', ')}',
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Mode toggle: Normal vs Recurring (one line) — no "Typ" icon/text anymore
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: SegmentedButton<bool>(
                                      segments: const [
                                        ButtonSegment<bool>(
                                          value: false,
                                          label: Text('Normal'),
                                          icon: Icon(Icons.event_rounded),
                                        ),
                                        ButtonSegment<bool>(
                                          value: true,
                                          label: Text('Wiederkehrend'),
                                          icon: Icon(Icons.autorenew_rounded),
                                        ),
                                      ],
                                      selected: {_recurringEnabled},
                                      onSelectionChanged: (s) =>
                                          _setMode(s.first),
                                    ),
                                  ),
                                ],
                              ),
                              if (_recurringEnabled) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Als „Erledigt“ markierte Aufgaben erscheinen nächste Woche wieder als offen.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (!_recurringEnabled) ...[
                        Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.schedule_rounded),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _formatDueLocal(_dueLocal),
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _pickNormalDueAt,
                                    icon: const Icon(
                                      Icons.edit_calendar_rounded,
                                    ),
                                    label: const Text('Fälligkeit'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      if (_recurringEnabled) ...[
                        Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.repeat_rounded),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Wochentage',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final w in _weekdayOrder())
                                      ChoiceChip(
                                        label: Text(_weekdayLabel(w)),
                                        selected: _recurringWeekdays.contains(
                                          w,
                                        ),
                                        onSelected: (sel) {
                                          setState(() {
                                            if (sel) {
                                              _recurringWeekdays.add(w);
                                            } else {
                                              _recurringWeekdays.remove(w);
                                            }
                                          });
                                          _recomputeCanSubmit();
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _formatRecurringTime(
                                            _recurringDueTime,
                                          ),
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _pickRecurringDueTime,
                                    icon: const Icon(Icons.access_time_rounded),
                                    label: const Text('Fälligkeit'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _canSubmit ? _save : null,
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                            widget.isEdit ? 'Speichern' : 'Erstellen',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssigneePickerSheet extends StatefulWidget {
  final ApiClient api;
  final Set<String> initiallySelectedIds;
  final List<UserPickerDto> initiallySelectedUsers;

  const _AssigneePickerSheet({
    required this.api,
    required this.initiallySelectedIds,
    required this.initiallySelectedUsers,
  });

  @override
  State<_AssigneePickerSheet> createState() => _AssigneePickerSheetState();
}

class _AssigneePickerSheetState extends State<_AssigneePickerSheet> {
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<UserPickerDto> _users = const [];
  final Set<String> _selected = {};
  final Map<String, UserPickerDto> _selectedCache = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initiallySelectedIds);

    for (final u in widget.initiallySelectedUsers) {
      _selectedCache[u.id] = u;
    }

    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? query}) async {
    setState(() => _loading = true);
    try {
      final hidePhilister = await MemberPickerSettings.hidePhilister();
      final rawUsers = await widget.api.pickerUsers(query: query);
      final users = rawUsers
          .where((u) {
            return MemberStatuses.shouldShowInPicker(
              memberStatus: u.memberStatus,
              hidePhilister: hidePhilister,
              forceShow: _selected.contains(u.id),
            );
          })
          .toList(growable: false);

      users.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      for (final u in users) {
        if (_selected.contains(u.id)) {
          _selectedCache[u.id] = u;
        }
      }

      if (!mounted) return;
      setState(() => _users = List<UserPickerDto>.unmodifiable(users));
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(UserPickerDto u) {
    setState(() {
      if (_selected.contains(u.id)) {
        _selected.remove(u.id);
      } else {
        _selected.add(u.id);
        _selectedCache[u.id] = u;
      }
    });
  }

  void _done() {
    final out = <UserPickerDto>[];

    for (final id in _selected) {
      final cached = _selectedCache[id];
      if (cached != null) {
        out.add(cached);
        continue;
      }

      final hit = _users.where((x) => x.id == id);
      if (hit.isNotEmpty) out.add(hit.first);
    }

    out.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    Navigator.pop(context, List<UserPickerDto>.unmodifiable(out));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: 520,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nutzer suchen',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (v) =>
                            _load(query: v.trim().isEmpty ? null : v.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _done,
                      child: Text('OK (${_selected.length})'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, i) {
                          final u = _users[i];
                          final checked = _selected.contains(u.id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (_) => _toggle(u),
                            title: Text(
                              MemberStatuses.pickerDisplayName(
                                displayName: u.displayName,
                                memberStatus: u.memberStatus,
                              ),
                            ),
                            subtitle: null,
                            titleAlignment: ListTileTitleAlignment.center,
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
