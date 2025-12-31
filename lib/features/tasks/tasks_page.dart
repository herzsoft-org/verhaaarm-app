import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
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
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
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
        content: Text('„${t.title}“ löschen?'),
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
              ..._tasks.map(
                    (t) => _TaskCard(
                  task: t,
                  onToggleSolved: () => _toggleSolved(t),
                  onDelete: () => _deleteTask(t),
                ),
              ),
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

  void _showAssigneesDialog(BuildContext context) {
    final names = task.assignees.map((u) => u.displayName.trim()).where((s) => s.isNotEmpty).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Beauftragte Bbr. (${names.length})'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: names.isEmpty
              ? const Text('Keine Empfänger.')
              : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final n in names)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(n),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      decoration: task.solved ? TextDecoration.lineThrough : null,
    );

    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: task.solved ? cs.onSurfaceVariant : cs.onSurface,
      decoration: task.solved ? TextDecoration.lineThrough : null,
    );

    final assigneeCount = task.assignees.length;

    return Card(
      color: task.solved ? cs.surfaceContainerLowest : cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onToggleSolved, // circle icon toggles solved
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        task.solved
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: titleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (task.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.description,
                          style: bodyStyle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<_TaskMenuAction>(
                  tooltip: 'Aktionen',
                  onSelected: (a) {
                    switch (a) {
                      case _TaskMenuAction.toggleSolved:
                        onToggleSolved();
                        break;
                      case _TaskMenuAction.delete:
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: _TaskMenuAction.toggleSolved,
                      child: Row(
                        children: [
                          Icon(task.solved ? Icons.undo_rounded : Icons.check_rounded),
                          const SizedBox(width: 10),
                          Text(task.solved ? 'Wieder offen' : 'Erledigt'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _TaskMenuAction.delete,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded),
                          SizedBox(width: 10),
                          Text('Löschen'),
                        ],
                      ),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.more_vert_rounded),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Bottom row: assignees summary + erledigt button
            Row(
              children: [
                if (assigneeCount == 0)
                  Chip(
                    label: const Text('Keine Empfänger'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  )
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showAssigneesDialog(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline_rounded, size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            '$assigneeCount',
                            style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
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

enum _TaskMenuAction { toggleSolved, delete }
