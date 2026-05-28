import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/api_error_text.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../common/widgets/member_picker_sheet.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

class PaukstundeFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final bool fechtwartMode;
  final PaukstundenEntryDto? editEntry;

  const PaukstundeFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.fechtwartMode = false,
    this.editEntry,
  });

  @override
  State<PaukstundeFormPage> createState() => _PaukstundeFormPageState();
}

class _PaukstundeFormPageState extends State<PaukstundeFormPage> {
  final _formKey = GlobalKey<FormState>();

  DateTime _date = DateTime.now();
  int _hours = 1;
  bool _loading = true;
  bool _saving = false;
  List<UserPickerDto> _allUsers = const [];
  Set<String> _selectedIds = {};

  bool get _isEdit => widget.editEntry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.editEntry;
    if (entry != null) {
      _date = DateTime.tryParse(entry.date) ?? DateTime.now();
      _hours = entry.hours < 1 ? 1 : entry.hours;
      _selectedIds = entry.participants.map((p) => p.id).toSet();
    }
    _loadUsers();
  }

  String get _dateIso {
    return DateFormat('yyyy-MM-dd').format(_date);
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final users = await widget.api.pickerUsers();
      UserDto? me;
      try {
        me = await widget.api.getMe();
      } catch (_) {
        me = null;
      }

      final selected = {..._selectedIds};
      if (!widget.fechtwartMode &&
          !_isEdit &&
          me != null &&
          users.any((u) => u.id == me!.id)) {
        selected.add(me.id);
      }

      if (!mounted) return;
      setState(() {
        _allUsers = users;
        _selectedIds = selected;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFriendlyApiError(
              e,
              fallback: 'Mitglieder konnten nicht geladen werden.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickParticipants() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          MemberPickerSheet(api: widget.api, initialSelectedIds: _selectedIds),
    );

    if (result == null || !mounted) return;
    setState(() => _selectedIds = result);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens einen Teilnehmer auswählen.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final participantUserIds = _selectedIds.toList(growable: false);
      final entry = widget.editEntry;

      if (entry == null) {
        await widget.api.createPaukstunde(
          CreatePaukstundeRequest(
            date: _dateIso,
            hours: _hours,
            participantUserIds: participantUserIds,
          ),
        );
      } else {
        await widget.api.updatePaukstunde(
          entry.id,
          UpdatePaukstundeRequest(
            date: _dateIso,
            hours: _hours,
            participantUserIds: participantUserIds,
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? 'Paukstunde gespeichert.' : 'Paukstunde eingetragen.',
          ),
        ),
      );

      if (Navigator.of(context).canPop()) {
        context.pop(true);
      } else {
        context.go(
          widget.fechtwartMode ? '/office/fechtwart' : '/paukstunden/me',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFriendlyApiError(
              e,
              fallback: 'Paukstunde konnte nicht gespeichert werden.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _participantSummary() {
    if (_selectedIds.isEmpty) return 'Keine Teilnehmer ausgewählt';
    final selected = _allUsers
        .where((u) => _selectedIds.contains(u.id))
        .toList();
    if (selected.isEmpty) return '${_selectedIds.length} ausgewählt';
    return selected
        .map(
          (u) => MemberStatuses.pickerDisplayName(
            displayName: u.displayName,
            memberStatus: u.memberStatus,
          ),
        )
        .join(', ');
  }

  void _changeHours(int delta) {
    setState(() {
      final next = _hours + delta;
      _hours = next < 1 ? 1 : next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEdit
          ? 'Paukstunde bearbeiten'
          : (widget.fechtwartMode
                ? 'Paukstunde eintragen'
                : 'Meine Paukstunde'),
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: (_loading || _saving) ? null : _save,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.event_rounded),
                          title: const Text('Datum'),
                          subtitle: Text(Format.dateOnlyShort(_dateIso)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          titleAlignment: ListTileTitleAlignment.center,
                          onTap: _pickDate,
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: FormField<int>(
                            initialValue: _hours,
                            validator: (_) {
                              if (_hours < 1) return 'Muss größer als 0 sein.';
                              return null;
                            },
                            builder: (state) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    'Paukstunden',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _HoursRow(
                                  value: _hours,
                                  onMinus: (_saving || _hours <= 1)
                                      ? null
                                      : () => _changeHours(-1),
                                  onPlus: _saving
                                      ? null
                                      : () => _changeHours(1),
                                ),
                                if (state.hasError) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    state.errorText!,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.group_rounded),
                      title: const Text('Teilnehmer'),
                      subtitle: Text(_participantSummary()),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      titleAlignment: ListTileTitleAlignment.center,
                      onTap: _pickParticipants,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _isEdit ? 'Änderungen speichern' : 'Eintragen',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HoursRow extends StatelessWidget {
  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _HoursRow({
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Anzahl', style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onMinus,
                  icon: const Icon(Icons.remove_rounded),
                  tooltip: 'Weniger',
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 52),
                  alignment: Alignment.center,
                  child: Text('$value', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: onPlus,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Mehr',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
