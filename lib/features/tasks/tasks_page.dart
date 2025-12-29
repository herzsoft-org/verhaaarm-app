import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class TasksPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const TasksPage({super.key, required this.api, required this.authStore});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _loading = true;
  bool _refreshing = false;

  List<TaskDto> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) {
      setState(() {
        if (_tasks.isEmpty) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final tasks = await widget.api.listMyTasks();
      tasks.sort((a, b) {
        // unsolved first, then newest first
        if (a.solved != b.solved) return a.solved ? 1 : -1;
        return b.createdAt.compareTo(a.createdAt);
      });

      if (!mounted) return;
      setState(() {
        _tasks = List<TaskDto>.unmodifiable(tasks);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arbeitsaufträge laden fehlgeschlagen: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _toggleSolved(TaskDto t) async {
    try {
      final updated = await widget.api.setTaskSolved(t.id, solved: !t.solved);
      if (!mounted) return;

      final list = _tasks.toList(growable: true);
      final idx = list.indexWhere((x) => x.id == t.id);
      if (idx >= 0) list[idx] = updated;

      list.sort((a, b) {
        if (a.solved != b.solved) return a.solved ? 1 : -1;
        return b.createdAt.compareTo(a.createdAt);
      });

      setState(() => _tasks = List<TaskDto>.unmodifiable(list));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status ändern fehlgeschlagen: $e')),
      );
    }
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
      setState(() => _tasks = List<TaskDto>.unmodifiable(_tasks.where((x) => x.id != t.id)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _deleteAllSolved() async {
    final solvedCount = _tasks.where((t) => t.solved).length;
    if (solvedCount == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erledigte löschen'),
        content: Text('Alle erledigten Arbeitsaufträge ($solvedCount) löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await widget.api.deleteAllSolvedMyTasks();
      if (!mounted) return;
      setState(() => _tasks = List<TaskDto>.unmodifiable(_tasks.where((t) => !t.solved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erledigte löschen fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unsolved = _tasks.where((t) => !t.solved).length;
    final solved = _tasks.where((t) => t.solved).length;

    return AppScaffold(
      title: 'Arbeitsaufträge',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
        IconButton(
          tooltip: 'Neu',
          icon: const Icon(Icons.add_rounded),
          onPressed: () => context.push('/tasks/new'),
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

            // NEW: Disclaimer
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Hinweis: Wenn ein Arbeitsauftrag mehrere Empfänger hat, dann wirkt „Erledigt markieren“ '
                            'und „Löschen“ für alle Nutzer, die diesen Auftrag haben.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.assignment_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Unerledigt: $unsolved · Erledigt: $solved',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: solved == 0 ? null : _deleteAllSolved,
                      child: const Text('Erledigte löschen'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Keine Arbeitsaufträge.')),
              )
            else
              ..._tasks.map((t) => _TaskCard(
                task: t,
                onToggleSolved: () => _toggleSolved(t),
                onDelete: () => _deleteTask(t),
              )),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskDto task;
  final VoidCallback onToggleSolved;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onToggleSolved,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: task.solved ? cs.surfaceContainerLowest : cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(task.solved ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      decoration: task.solved ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Löschen',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (task.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(task.description, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (task.assignees.isEmpty)
                  const Chip(label: Text('Keine Empfänger'))
                else
                  for (final u in task.assignees)
                    Chip(
                      label: Text(u.displayName),
                      visualDensity: VisualDensity.compact,
                    ),
              ],
            ),

            // CHANGED: Removed "Erstellt/Erledigt" line entirely
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: onToggleSolved,
                  icon: Icon(task.solved ? Icons.undo_rounded : Icons.check_rounded),
                  label: Text(task.solved ? 'Wieder offen' : 'Erledigt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
