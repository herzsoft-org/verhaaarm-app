import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class OfficeTasksPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const OfficeTasksPage({super.key, required this.api, required this.authStore});

  @override
  State<OfficeTasksPage> createState() => _OfficeTasksPageState();
}

class _OfficeTasksPageState extends State<OfficeTasksPage> {
  bool _loading = true;
  bool _refreshing = false;

  List<TaskDto> _all = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        if (_all.isEmpty) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final tasks = await widget.api.listAdminTasks();
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() => _all = List<TaskDto>.unmodifiable(tasks));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arbeitsaufträge laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Map<String, _UserGroup> _groupByAssignee() {
    final Map<String, _UserGroup> map = {};

    for (final t in _all) {
      if (t.assignees.isEmpty) {
        map
            .putIfAbsent(
          '__NONE__',
              () => _UserGroup(
            key: '__NONE__',
            displayName: 'Ohne Empfänger',
            username: '',
          ),
        )
            .tasks
            .add(t);
        continue;
      }

      for (final u in t.assignees) {
        map
            .putIfAbsent(
          u.id,
              () => _UserGroup(
            key: u.id,
            displayName: u.displayName,
            username: u.username,
          ),
        )
            .tasks
            .add(t);
      }
    }

    final entries = map.entries.toList(growable: false);
    entries.sort((a, b) => a.value.displayName.toLowerCase().compareTo(b.value.displayName.toLowerCase()));

    return {for (final e in entries) e.key: e.value};
  }

  Future<void> _deleteTask(TaskDto t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arbeitsauftrag löschen'),
        content: Text('„${t.title}“ wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.api.deleteTask(t.id);
      if (!mounted) return;
      setState(() => _all = List<TaskDto>.unmodifiable(_all.where((x) => x.id != t.id)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _toggleSolved(TaskDto t) async {
    try {
      final updated = await widget.api.setTaskSolved(t.id, solved: !t.solved);
      if (!mounted) return;

      final list = _all.toList(growable: true);
      final idx = list.indexWhere((x) => x.id == t.id);
      if (idx >= 0) list[idx] = updated;
      setState(() => _all = List<TaskDto>.unmodifiable(list));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status ändern fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByAssignee();

    return AppScaffold(
      title: 'Arbeitsaufträge (Admin)',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_refreshing) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            ],
            if (_all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Keine Arbeitsaufträge.')),
              )
            else
              ...grouped.values.map((g) {
                final tasks = g.tasks.toList(growable: false);
                tasks.sort((a, b) {
                  if (a.solved != b.solved) return a.solved ? 1 : -1;
                  return b.createdAt.compareTo(a.createdAt);
                });

                final unsolved = tasks.where((t) => !t.solved).length;

                return Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.person_rounded),
                    title: Text(g.displayName),
                    subtitle: Text('$unsolved offen · ${tasks.length} gesamt'),
                    children: [
                      for (final t in tasks)
                        ListTile(
                          leading: Icon(t.solved ? Icons.check_circle_rounded : Icons.assignment_rounded),
                          title: Text(t.title),
                          subtitle: Text(
                            '${t.description}\n'
                                'Erstellt: ${Format.dateTimeShort(t.createdAt)}'
                                '${t.solvedAt == null ? '' : ' · Erledigt: ${Format.dateTimeShort(t.solvedAt!)}'}',
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: t.solved ? 'Wieder offen' : 'Erledigt',
                                icon: Icon(t.solved ? Icons.undo_rounded : Icons.check_rounded),
                                onPressed: () => _toggleSolved(t),
                              ),
                              IconButton(
                                tooltip: 'Bearbeiten',
                                icon: const Icon(Icons.edit_rounded),
                                onPressed: () => context.push('/office/tasks/${t.id}/edit', extra: t),
                              ),
                              IconButton(
                                tooltip: 'Löschen',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => _deleteTask(t),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _UserGroup {
  final String key;
  final String displayName;
  final String username;
  final List<TaskDto> tasks = [];

  _UserGroup({required this.key, required this.displayName, required this.username});
}
