import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/format.dart';
import '../../common/member_picker_settings.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

class FerienvertreterFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final FerienvertreterDto? editEntry;

  const FerienvertreterFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.editEntry,
  });

  @override
  State<FerienvertreterFormPage> createState() =>
      _FerienvertreterFormPageState();
}

class _FerienvertreterFormPageState extends State<FerienvertreterFormPage> {
  bool _saving = false;

  UserPickerDto? _person;
  DateTime? _fromDate;
  DateTime? _untilDate;

  bool get _isEdit => widget.editEntry != null;

  @override
  void initState() {
    super.initState();

    final entry = widget.editEntry;
    if (entry != null) {
      _person = UserPickerDto(
        id: entry.person.id,
        username: entry.person.username,
        displayName: entry.person.displayName,
        memberStatus: entry.person.memberStatus,
        actividad: entry.person.aktivitas,
        disabled: entry.person.disabled,
      );
      _fromDate = entry.fromDateLocal;
      _untilDate = entry.untilDateLocal;
    } else {
      final now = DateTime.now();
      _fromDate = DateTime(now.year, now.month, now.day);
      _untilDate = _fromDate;
    }
  }

  static String _fmtLocalDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _pickPerson() async {
    final result = await showModalBottomSheet<UserPickerDto>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PersonPickerSheet(
        api: widget.api,
        initiallySelectedId: _person?.id,
      ),
    );
    if (result == null) return;
    setState(() => _person = result);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = (isFrom ? _fromDate : _untilDate) ??
        DateTime(now.year, now.month, now.day);

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null) return;

    setState(() {
      if (isFrom) {
        _fromDate = date;
        if (_untilDate != null && _untilDate!.isBefore(date)) {
          _untilDate = date;
        }
      } else {
        _untilDate = date;
      }
    });
  }

  bool get _canSave =>
      !_saving && _person != null && _fromDate != null && _untilDate != null;

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.api.updateFerienvertreter(
          widget.editEntry!.id,
          UpdateFerienvertreterRequest(
            userId: _person!.id,
            fromDate: _fmtLocalDate(_fromDate!),
            untilDate: _fmtLocalDate(_untilDate!),
          ),
        );
      } else {
        await widget.api.createFerienvertreter(
          CreateFerienvertreterRequest(
            userId: _person!.id,
            fromDate: _fmtLocalDate(_fromDate!),
            untilDate: _fmtLocalDate(_untilDate!),
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Löschen?'),
        content: const Text('Diesen Ferienvertreter wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await widget.api.deleteFerienvertreter(widget.editEntry!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gelöscht.')));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEdit ? 'Ferienvertreter bearbeiten' : 'Ferienvertreter anlegen',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        if (_isEdit)
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_rounded),
            onPressed: _saving ? null : _delete,
          ),
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: _canSave ? _save : null,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: const Icon(Icons.person_rounded),
              title: Text(
                _person == null
                    ? 'Person wählen'
                    : MemberStatuses.pickerDisplayName(
                        displayName: _person!.displayName,
                        memberStatus: _person!.memberStatus,
                      ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _saving ? null : _pickPerson,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  titleAlignment: ListTileTitleAlignment.center,
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('Von'),
                  trailing: Text(
                    _fromDate == null
                        ? '—'
                        : Format.dateShort(_fmtLocalDate(_fromDate!)),
                  ),
                  onTap: _saving ? null : () => _pickDate(isFrom: true),
                ),
                const Divider(height: 1),
                ListTile(
                  titleAlignment: ListTileTitleAlignment.center,
                  leading: const Icon(Icons.event_busy_rounded),
                  title: const Text('Bis'),
                  trailing: Text(
                    _untilDate == null
                        ? '—'
                        : Format.dateShort(_fmtLocalDate(_untilDate!)),
                  ),
                  onTap: _saving ? null : () => _pickDate(isFrom: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canSave ? _save : null,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Speichern'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonPickerSheet extends StatefulWidget {
  final ApiClient api;
  final String? initiallySelectedId;

  const _PersonPickerSheet({required this.api, this.initiallySelectedId});

  @override
  State<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends State<_PersonPickerSheet> {
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<UserPickerDto> _users = const [];

  @override
  void initState() {
    super.initState();
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
      final rawUsers = await widget.api.pickerUsers(
        query: query,
        activeOnly: false,
      );
      final users = rawUsers
          .where((u) {
            return MemberStatuses.shouldShowInPicker(
              memberStatus: u.memberStatus,
              hidePhilister: hidePhilister,
              forceShow: u.id == widget.initiallySelectedId,
            );
          })
          .toList(growable: false);

      users.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      if (!mounted) return;
      setState(() => _users = List<UserPickerDto>.unmodifiable(users));
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: 560,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
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
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, i) {
                          final u = _users[i];
                          final cs = Theme.of(context).colorScheme;
                          return ListTile(
                            titleAlignment: ListTileTitleAlignment.center,
                            selected: u.id == widget.initiallySelectedId,
                            title: Text(
                              MemberStatuses.pickerDisplayName(
                                displayName: u.displayName,
                                memberStatus: u.memberStatus,
                              ),
                              style: u.disabled
                                  ? TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: cs.onSurfaceVariant,
                                    )
                                  : null,
                            ),
                            subtitle: u.disabled
                                ? const Text('Gesperrt')
                                : null,
                            onTap: () => Navigator.pop(context, u),
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
