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

  const PaukstundeFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.fechtwartMode = false,
  });

  @override
  State<PaukstundeFormPage> createState() => _PaukstundeFormPageState();
}

class _PaukstundeFormPageState extends State<PaukstundeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _hoursCtrl = TextEditingController(text: '1');

  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  List<UserPickerDto> _allUsers = const [];
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    super.dispose();
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

      final selected = <String>{};
      if (me != null && users.any((u) => u.id == me!.id)) {
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
      await widget.api.createPaukstunde(
        CreatePaukstundeRequest(
          date: _dateIso,
          hours: int.parse(_hoursCtrl.text.trim()),
          participantUserIds: _selectedIds.toList(growable: false),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Paukstunde eingetragen.')));

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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.fechtwartMode ? 'Paukstunde eintragen' : 'Meine Paukstunde',
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
                          child: TextFormField(
                            controller: _hoursCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Paukstunden',
                              prefixIcon: Icon(Icons.timer_rounded),
                            ),
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null) {
                                return 'Bitte ganze Zahl eingeben.';
                              }
                              if (n <= 0) return 'Muss größer als 0 sein.';
                              return null;
                            },
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
                      label: const Text('Eintragen'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
