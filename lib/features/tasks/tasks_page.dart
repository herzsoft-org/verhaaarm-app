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

  void _sortTasks(List<TaskDto> tasks) {
    tasks.sort((a, b) {
      if (a.solved != b.solved) return a.solved ? 1 : -1;

      if (!a.solved) {
        // Unsolved: dueAt asc (null last), then createdAt desc
        final ad = a.dueAt;
        final bd = b.dueAt;
        if (ad == null && bd != null) return 1;
        if (ad != null && bd == null) return -1;
        if (ad != null && bd != null) {
          final c = ad.compareTo(bd);
          if (c != 0) return c;
        }
      }

      return b.createdAt.compareTo(a.createdAt);
    });
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
      _sortTasks(tasks);

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

      _sortTasks(list);
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

  Future<void> _editTask(TaskDto t) async {
    try {
      if (!mounted) return;

      final changed = await context.push<TaskDto>(
        '/tasks/${t.id}/edit',
        extra: t,
      );

      if (changed != null && mounted) {
        await _load(force: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bearbeiten öffnen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _deleteAllSolved() async {
    // IMPORTANT: recurring solved tasks are NOT affected by "delete all solved"
    final solvedNonRecurring = _tasks.where((t) => t.solved && !t.recurringEnabled).toList(growable: false);
    final solvedCount = solvedNonRecurring.length;
    if (solvedCount == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erledigte löschen'),
        content: Text('Alle erledigten Arbeitsaufträge ($solvedCount) löschen?\n'
            'Wöchentliche Arbeitsaufträge werden nicht entfernt.'),
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

      setState(() {
        _tasks = List<TaskDto>.unmodifiable(
          _tasks.where((t) => !(t.solved && !t.recurringEnabled)),
        );
      });
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

    final solvedNonRecurring = _tasks.where((t) => t.solved && !t.recurringEnabled).length;

    return AppScaffold(
      title: 'Arbeitsaufträge',
      showNotificationButton: false,
      showProfileButton: false,
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
        IconButton(
          tooltip: 'Neu',
          icon: const Icon(Icons.add_rounded),
          onPressed: () async {
            final changed = await context.push<TaskDto>('/tasks/new');
            if (changed != null && mounted) {
              await _load(force: true);
            }
          },
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
                        'Unerledigt: $unsolved',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: solvedNonRecurring == 0 ? null : _deleteAllSolved,
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
                  onEdit: () => _editTask(t),
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
  final VoidCallback onEdit;

  const _TaskCard({
    required this.task,
    required this.onToggleSolved,
    required this.onDelete,
    required this.onEdit,
  });

  void _showAssigneesDialog(BuildContext context) {
    String display(UserPickerDto u) {
      final dn = u.displayName.trim();
      if (dn.isNotEmpty) return dn;
      final un = u.username.trim();
      if (un.isNotEmpty) return un;
      return '(unbekannt)';
    }

    final names = task.assignees.map(display).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

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

  int _weekdayOrder(String w) {
    switch (w) {
      case 'MON':
        return 1;
      case 'TUE':
        return 2;
      case 'WED':
        return 3;
      case 'THU':
        return 4;
      case 'FRI':
        return 5;
      case 'SAT':
        return 6;
      case 'SUN':
        return 7;
      default:
        return 99;
    }
  }

  void _showWeekdaysDialog(BuildContext context) {
    final days = task.recurringWeekdays.toList(growable: false)
      ..sort((a, b) => _weekdayOrder(a).compareTo(_weekdayOrder(b)));

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


  String _ddMmHm(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}'
        ' - ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _ddMmYyyyHm(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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

    final recurringDays = task.recurringWeekdays.toList(growable: false)
      ..sort((a, b) => _weekdayOrder(a).compareTo(_weekdayOrder(b)));

    return Card(
      color: task.solved ? cs.surfaceContainerLowest : cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: circle, date badge, title, menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.center, // <-- changed for vertical centering
              children: [
                InkWell( // <-- removed top padding so it centers nicely
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
                const SizedBox(width: 10),
                if (due != null) ...[
                  Tooltip(
                    message: _ddMmYyyyHm(due),
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
                            _ddMmHm(due),
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
                const SizedBox(width: 6),
                PopupMenuButton<_TaskMenuAction>(
                  tooltip: 'Aktionen',
                  onSelected: (a) {
                    switch (a) {
                      case _TaskMenuAction.edit:
                        onEdit();
                        break;
                      case _TaskMenuAction.toggleSolved:
                        onToggleSolved();
                        break;
                      case _TaskMenuAction.delete:
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: _TaskMenuAction.edit,
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded),
                          SizedBox(width: 10),
                          Text('Bearbeiten'),
                        ],
                      ),
                    ),
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
            if (task.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.description,
                style: bodyStyle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),

            // Bottom row: assignees icon, weekdays icon, open/close button
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
                  Tooltip(
                    message: 'Empfänger anzeigen',
                    child: InkWell(
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
                              'Wiederkehrend',
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
                  )
                else
                  Tooltip(
                    message: 'Nicht wiederkehrend',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.autorenew_rounded, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.55)),
                          const SizedBox(width: 6),
                          Text(
                            'Einmalig',
                            style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.75)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onToggleSolved,
                  child: Text(task.solved ? 'Öffnen' : 'Erledigt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _TaskMenuAction { edit, toggleSolved, delete }
