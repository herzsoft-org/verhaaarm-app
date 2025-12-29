import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

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

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _titleCtrl.text = i.title;
      _descCtrl.text = i.description;
      _assignees = List<UserPickerDto>.from(i.assignees);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAssignees() async {
    final selectedIds = _assignees.map((e) => e.id).toSet();

    final result = await showModalBottomSheet<List<UserPickerDto>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AssigneePickerSheet(
        api: widget.api,
        initiallySelectedIds: selectedIds,
      ),
    );

    if (result == null) return;
    setState(() => _assignees = List<UserPickerDto>.unmodifiable(result));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_assignees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mindestens ein Empfänger ist Pflicht.')),
      );
      return;
    }

    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final assigneeIds = _assignees.map((e) => e.id).toList(growable: false);

    setState(() => _saving = true);

    try {
      if (widget.isEdit) {
        final id = widget.initial!.id;
        await widget.api.updateTask(id, UpdateTaskRequest(title: title, description: desc, assigneeUserIds: assigneeIds));
      } else {
        await widget.api.createTask(CreateTaskRequest(title: title, description: desc, assigneeUserIds: assigneeIds));
      }

      if (!mounted) return;
      context.pop(true);
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
    final title = widget.isEdit ? 'Arbeitsauftrag bearbeiten' : 'Arbeitsauftrag erstellen';

    return AppScaffold(
      title: title,
      actions: [
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: _saving ? null : _save,
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
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_rounded),
                          label: Text(widget.isEdit ? 'Speichern' : 'Erstellen'),
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

  const _AssigneePickerSheet({
    required this.api,
    required this.initiallySelectedIds,
  });

  @override
  State<_AssigneePickerSheet> createState() => _AssigneePickerSheetState();
}

class _AssigneePickerSheetState extends State<_AssigneePickerSheet> {
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<UserPickerDto> _users = const [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initiallySelectedIds);
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
      final users = await widget.api.pickerUsers(query: query);
      users.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      if (!mounted) return;
      setState(() => _users = List<UserPickerDto>.unmodifiable(users));
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _done() {
    final selectedUsers = _users.where((u) => _selected.contains(u.id)).toList(growable: false);
    Navigator.pop(context, selectedUsers);
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
                        onChanged: (v) => _load(query: v.trim().isEmpty ? null : v.trim()),
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
                      onChanged: (_) => _toggle(u.id),
                      title: Text(u.displayName),
                      // CHANGED: no username shown
                      subtitle: null,
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
