import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

enum _FerienvertreterStatus { past, current, future }

class FerienvertreterPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const FerienvertreterPage({
    super.key,
    required this.api,
    required this.authStore,
  });

  @override
  State<FerienvertreterPage> createState() => _FerienvertreterPageState();
}

class _FerienvertreterPageState extends State<FerienvertreterPage> {
  bool _loading = true;
  bool _canEdit = false;
  List<FerienvertreterDto> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        widget.api.listFerienvertreter(),
        widget.api.getAmtCanEdit(),
      ]);

      final entries = (results[0] as List<FerienvertreterDto>).toList()
        ..sort((a, b) => a.fromDateLocal.compareTo(b.fromDateLocal));

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _canEdit = results[1] as bool;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ferienvertreter laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final changed = await context.push<bool>('/ferienvertreter/new');
    if (changed == true && mounted) await _load();
  }

  Future<void> _openEdit(FerienvertreterDto entry) async {
    final changed = await context.push<bool>(
      '/ferienvertreter/${entry.id}/edit',
      extra: entry,
    );
    if (changed == true && mounted) await _load();
  }

  _FerienvertreterStatus _statusOf(FerienvertreterDto e) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (today.isBefore(e.fromDateLocal)) return _FerienvertreterStatus.future;
    if (today.isAfter(e.untilDateLocal)) return _FerienvertreterStatus.past;
    return _FerienvertreterStatus.current;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ferienvertreter',
      showNotificationButton: false,
      showProfileButton: false,
      onRefresh: _load,
      actions: [
        if (_canEdit)
          IconButton(
            tooltip: 'Neu',
            icon: const Icon(Icons.add_rounded),
            onPressed: _loading ? null : _openCreate,
          ),
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(12),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              'Es sind keine Semesterferien oder keine '
                              'Ferienvertreter gewählt.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final entry in _entries)
                          _FerienvertreterCard(
                            entry: entry,
                            status: _statusOf(entry),
                            canEdit: _canEdit,
                            onTap: () => _openEdit(entry),
                          ),
                      ],
                    ),
            ),
    );
  }
}

class _FerienvertreterCard extends StatelessWidget {
  final FerienvertreterDto entry;
  final _FerienvertreterStatus status;
  final bool canEdit;
  final VoidCallback onTap;

  const _FerienvertreterCard({
    required this.entry,
    required this.status,
    required this.canEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color? cardColor;
    Color textColor = cs.onSurface;
    var opacity = 1.0;

    switch (status) {
      case _FerienvertreterStatus.past:
        opacity = 0.55;
        break;
      case _FerienvertreterStatus.current:
        cardColor = cs.primaryContainer;
        textColor = cs.onPrimaryContainer;
        break;
      case _FerienvertreterStatus.future:
        break;
    }

    final displayName = MemberStatuses.pickerDisplayName(
      displayName: entry.person.displayName,
      memberStatus: entry.person.memberStatus,
    );

    return Opacity(
      opacity: opacity,
      child: Card(
        color: cardColor,
        child: ListTile(
          titleAlignment: ListTileTitleAlignment.center,
          title: Text(
            displayName,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${Format.dateShort(entry.fromDate)} – ${Format.dateShort(entry.untilDate)}',
            style: TextStyle(color: textColor),
          ),
          trailing: canEdit
              ? Icon(Icons.chevron_right_rounded, color: textColor)
              : null,
          onTap: canEdit ? onTap : null,
        ),
      ),
    );
  }
}
