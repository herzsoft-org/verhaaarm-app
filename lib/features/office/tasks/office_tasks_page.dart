import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../common/widgets/busy_icon_button.dart';
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

  Future<void> _openCreateTask() async {
    final changed = await context.push<TaskDto>('/office/tasks/new');
    if (changed != null && mounted) {
      await _load(force: true);
    }
  }

  Future<void> _openEditTask(TaskDto t) async {
    final changed = await context.push<TaskDto>(
      '/office/tasks/${t.id}/edit',
      extra: t,
    );

    if (changed != null && mounted) {
      await _load(force: true);
    }
  }

  String _fmt(DateTime dt) => Format.dateTimeShort(dt.toIso8601String());

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
      title: 'Arbeitsaufträge',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        BusyIconButton(
          busy: _loading || _refreshing,
          tooltip: 'Neu laden',
          icon: Icons.refresh_rounded,
          onPressed: () => _load(force: true),
        ),
        IconButton(
          tooltip: 'Neu',
          icon: const Icon(Icons.add_rounded),
          onPressed: _openCreateTask,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          children: [
                            for (final t in tasks) ...[
                              _AdminTaskCard(
                                task: t,
                                fmt: _fmt,
                                onToggleSolved: () => _toggleSolved(t),
                                onEdit: () => _openEditTask(t),
                                onDelete: () => _deleteTask(t),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
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

class _AdminTaskCard extends StatelessWidget {
  final TaskDto task;
  final String Function(DateTime) fmt;
  final VoidCallback onToggleSolved;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AdminTaskCard({
    required this.task,
    required this.fmt,
    required this.onToggleSolved,
    required this.onEdit,
    required this.onDelete,
  });

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

  void _showWeekdaysDialog(BuildContext context) {
    final days = task.recurringWeekdays.toList(growable: false)..sort((a, b) => a.compareTo(b));

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Wochentage (${days.length})'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: days.isEmpty
              ? const Text('Keine Wochentage gesetzt.')
              : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in days)
                Chip(
                  avatar: const Icon(Icons.today_rounded, size: 18),
                  label: Text(_weekdayLabel(d)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  String _ddMm(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final nowUtc = DateTime.now().toUtc();
    final due = task.dueAt;
    final isOverdue = !task.solved && due != null && due.toUtc().isBefore(nowUtc);

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      decoration: task.solved ? TextDecoration.lineThrough : null,
    );

    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: task.solved ? cs.onSurfaceVariant : cs.onSurface,
      decoration: task.solved ? TextDecoration.lineThrough : null,
    );

    final assigneeCount = task.assignees.length;
    final recurringDays = task.recurringWeekdays.toList(growable: false)..sort((a, b) => a.compareTo(b));

    return Card(
      color: task.solved ? cs.surfaceContainerLowest : null,
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
                    onTap: onToggleSolved,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        task.solved ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (due != null) ...[
                  Tooltip(
                    message: fmt(due),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOverdue ? cs.errorContainer : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: isOverdue ? cs.onErrorContainer : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _ddMm(due),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: isOverdue ? cs.onErrorContainer : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    task.title,
                    style: titleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<_AdminMenuAction>(
                  tooltip: 'Aktionen',
                  onSelected: (a) {
                    switch (a) {
                      case _AdminMenuAction.edit:
                        onEdit();
                        break;
                      case _AdminMenuAction.toggleSolved:
                        onToggleSolved();
                        break;
                      case _AdminMenuAction.delete:
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: _AdminMenuAction.edit,
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded),
                          SizedBox(width: 10),
                          Text('Bearbeiten'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _AdminMenuAction.toggleSolved,
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
                      value: _AdminMenuAction.delete,
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
            if (task.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.description,
                style: bodyStyle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Erstellt: ${fmt(task.createdAt)}'
                  '${task.solvedAt == null ? '' : ' · Erledigt: ${fmt(task.solvedAt!)}'}',
              style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Tooltip(
                  message: 'Empfänger (in dieser Ansicht gruppiert)',
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
                const SizedBox(width: 8),
                if (task.recurringEnabled)
                  Tooltip(
                    message: 'Wochentage anzeigen',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _showWeekdaysDialog(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.autorenew_rounded, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'Wiederk.',
                              style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            if (recurringDays.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '(${recurringDays.length})',
                                style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onToggleSolved,
                  child: Text(task.solved ? 'Wieder offen' : 'Erledigt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _AdminMenuAction { edit, toggleSolved, delete }

class _UserGroup {
  final String key;
  final String displayName;
  final String username;
  final List<TaskDto> tasks = [];

  _UserGroup({required this.key, required this.displayName, required this.username});
}