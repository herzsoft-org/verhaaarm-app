import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/member_picker_settings.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

class AemterPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const AemterPage({super.key, required this.api, required this.authStore});

  @override
  State<AemterPage> createState() => _AemterPageState();
}

class _AemterPageState extends State<AemterPage> {
  bool _loading = true;
  bool _editMode = false;
  AemterOverviewDto? _overview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final overview = await widget.api.getAemterOverview();
      if (!mounted) return;
      setState(() => _overview = overview);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ämter laden fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _currentUserHoldsAnyAmt {
    // Admins can manage anything, regardless of whether they personally hold an Amt.
    if (widget.authStore.currentRoles.contains(AppRole.admin)) return true;

    final overview = _overview;
    final myId = widget.authStore.currentUser?.id;
    if (overview == null || myId == null) return false;

    for (final group in overview.ehrengericht) {
      for (final line in group.lines) {
        if (line.holders.any((h) => h.userId == myId)) return true;
      }
    }
    for (final entry in overview.other) {
      if (entry.holders.any((h) => h.userId == myId)) return true;
    }
    return false;
  }

  // Sprecher/Fechtwart/Schmuckwart/Kassenwart are read from user roles; editing them here
  // bulk-reassigns that role, so it's gated the same as user administration (ADMIN/SENIOR),
  // not the "holds any Amt" rule used for the rest of the page.
  bool get _canEditAutoAemter {
    final roles = widget.authStore.currentRoles;
    return roles.contains(AppRole.admin) || roles.contains(AppRole.senior);
  }

  String _namesOrNichtVergeben(List<AmtHolderDto> holders) {
    if (holders.isEmpty) return 'Nicht vergeben';
    return holders.map((h) => h.displayName).join(', ');
  }

  Future<void> _editGroup(AmtGroupLineDto group) async {
    if (!_editMode || !_currentUserHoldsAnyAmt) return;

    final currentHolders = <AmtHolderDto>[
      for (final line in group.lines) ...line.holders,
    ];

    final result = await _showEditSheet(
      title: group.baseLabel,
      currentHolders: currentHolders,
    );
    if (result == null) return;

    await _save(group.amtType, result);
  }

  Future<void> _editEntry(AmtEntryDto entry) async {
    if (!_editMode) return;

    if (entry.autoFromRole) {
      if (!_canEditAutoAemter) return;

      final result = await _showEditSheet(
        title: entry.label,
        currentHolders: entry.holders,
      );
      if (result == null) return;

      await _saveAuto(entry.amtType, result);
      return;
    }

    if (!_currentUserHoldsAnyAmt) return;

    final result = await _showEditSheet(
      title: entry.label,
      currentHolders: entry.holders,
    );
    if (result == null) return;

    await _save(entry.amtType, result);
  }

  Future<List<UserPickerDto>?> _showEditSheet({
    required String title,
    required List<AmtHolderDto> currentHolders,
  }) {
    return showModalBottomSheet<List<UserPickerDto>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AmtHolderPickerSheet(
        api: widget.api,
        title: title,
        initiallySelectedIds: currentHolders.map((h) => h.userId).toSet(),
      ),
    );
  }

  Future<void> _save(String amtType, List<UserPickerDto> newHolders) async {
    try {
      await widget.api.setAmtHolders(
        amtType: amtType,
        userIds: newHolders.map((u) => u.id).toList(growable: false),
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    }
  }

  Future<void> _saveAuto(String autoAmt, List<UserPickerDto> newHolders) async {
    try {
      await widget.api.setAutoAmtHolders(
        autoAmt: autoAmt,
        userIds: newHolders.map((u) => u.id).toList(growable: false),
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final canEdit = _currentUserHoldsAnyAmt;

    return AppScaffold(
      title: 'Ämter',
      showNotificationButton: false,
      showProfileButton: false,
      onRefresh: _load,
      actions: [
        if (canEdit)
          IconButton(
            tooltip: _editMode ? 'Fertig' : 'Bearbeiten',
            icon: Icon(_editMode ? Icons.check_rounded : Icons.edit_rounded),
            onPressed: () => setState(() => _editMode = !_editMode),
          ),
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading || overview == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _EhrengerichtCard(
                    groups: overview.ehrengericht,
                    editMode: _editMode,
                    showEditAffordance: canEdit && _editMode,
                    onTap: _editGroup,
                    namesOrNichtVergeben: _namesOrNichtVergeben,
                  ),
                  const SizedBox(height: 12),
                  _OtherAemterCard(
                    // Outside of edit mode, Ämter merged into an Ehrengericht line stay
                    // hidden here to avoid showing the same name twice. In edit mode they
                    // reappear so they can still be edited individually.
                    entries: _editMode
                        ? overview.other
                        : overview.other
                              .where((e) => !e.mergedIntoEhrengericht)
                              .toList(growable: false),
                    canEditManual: canEdit && _editMode,
                    canEditAuto: _canEditAutoAemter && _editMode,
                    onTap: _editEntry,
                    namesOrNichtVergeben: _namesOrNichtVergeben,
                  ),
                ],
              ),
            ),
    );
  }
}

class _EhrengerichtCard extends StatelessWidget {
  final List<AmtGroupLineDto> groups;
  final bool editMode;
  final bool showEditAffordance;
  final void Function(AmtGroupLineDto group) onTap;
  final String Function(List<AmtHolderDto> holders) namesOrNichtVergeben;

  static const _spitze = {'X', 'XX', 'XXX'};

  const _EhrengerichtCard({
    required this.groups,
    required this.editMode,
    required this.showEditAffordance,
    required this.onTap,
    required this.namesOrNichtVergeben,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.tertiaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'Ehrengericht',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0 &&
                _spitze.contains(groups[i - 1].amtType) &&
                !_spitze.contains(groups[i].amtType))
              Divider(
                height: 17,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: cs.onTertiaryContainer.withValues(alpha: 0.3),
              ),
            // In edit mode every Ehrengericht slot is shown decoupled (its own plain
            // label, no "und X" combination) so it's never unclear that tapping it only
            // edits that one slot. Outside edit mode we keep the combined display.
            if (editMode)
              _row(
                context: context,
                title: groups[i].baseLabel,
                holders: [for (final line in groups[i].lines) ...line.holders],
                onTap: showEditAffordance ? () => onTap(groups[i]) : null,
              )
            else
              for (final line in groups[i].lines)
                _row(
                  context: context,
                  title: line.displayTitle,
                  holders: line.holders,
                  onTap: showEditAffordance ? () => onTap(groups[i]) : null,
                ),
          ],
        ],
      ),
    );
  }

  Widget _row({
    required BuildContext context,
    required String title,
    required List<AmtHolderDto> holders,
    required VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final unfilled = holders.isEmpty;

    return ListTile(
      titleAlignment: ListTileTitleAlignment.center,
      title: Text(title, style: TextStyle(color: cs.onTertiaryContainer)),
      subtitle: Text(
        namesOrNichtVergeben(holders),
        style: TextStyle(
          color: cs.onTertiaryContainer.withValues(alpha: unfilled ? 1 : 0.8),
          fontStyle: unfilled ? FontStyle.italic : FontStyle.normal,
          fontWeight: unfilled ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: onTap != null
          ? Icon(Icons.chevron_right_rounded, color: cs.onTertiaryContainer)
          : null,
      onTap: onTap,
    );
  }
}

class _OtherAemterCard extends StatelessWidget {
  final List<AmtEntryDto> entries;
  final bool canEditManual;
  final bool canEditAuto;
  final void Function(AmtEntryDto entry) onTap;
  final String Function(List<AmtHolderDto> holders) namesOrNichtVergeben;

  const _OtherAemterCard({
    required this.entries,
    required this.canEditManual,
    required this.canEditAuto,
    required this.onTap,
    required this.namesOrNichtVergeben,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'Weitere Ämter',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final entry in entries) _row(context, entry),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AmtEntryDto entry) {
    final canEdit = entry.autoFromRole ? canEditAuto : canEditManual;
    final unfilled = entry.holders.isEmpty;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      titleAlignment: ListTileTitleAlignment.center,
      title: Text(entry.label),
      subtitle: Text(
        namesOrNichtVergeben(entry.holders),
        style: unfilled
            ? TextStyle(
                color: cs.error,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      trailing: canEdit ? const Icon(Icons.chevron_right_rounded) : null,
      onTap: canEdit ? () => onTap(entry) : null,
    );
  }
}

class _AmtHolderPickerSheet extends StatefulWidget {
  final ApiClient api;
  final String title;
  final Set<String> initiallySelectedIds;

  const _AmtHolderPickerSheet({
    required this.api,
    required this.title,
    required this.initiallySelectedIds,
  });

  @override
  State<_AmtHolderPickerSheet> createState() => _AmtHolderPickerSheetState();
}

class _AmtHolderPickerSheetState extends State<_AmtHolderPickerSheet> {
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<UserPickerDto> _users = const [];
  final Set<String> _selected = {};
  final Map<String, UserPickerDto> _selectedCache = {};

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
              forceShow: _selected.contains(u.id),
            );
          })
          .toList(growable: false);

      users.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      for (final u in users) {
        if (_selected.contains(u.id)) {
          _selectedCache[u.id] = u;
        }
      }

      if (!mounted) return;
      setState(() => _users = List<UserPickerDto>.unmodifiable(users));
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(UserPickerDto u) {
    setState(() {
      if (_selected.contains(u.id)) {
        _selected.remove(u.id);
      } else {
        _selected.add(u.id);
        _selectedCache[u.id] = u;
      }
    });
  }

  void _done() {
    final out = <UserPickerDto>[];

    for (final id in _selected) {
      final cached = _selectedCache[id];
      if (cached != null) {
        out.add(cached);
        continue;
      }

      final hit = _users.where((x) => x.id == id);
      if (hit.isNotEmpty) out.add(hit.first);
    }

    out.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    Navigator.pop(context, List<UserPickerDto>.unmodifiable(out));
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  children: [
                    Expanded(
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
                          final cs = Theme.of(context).colorScheme;
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (_) => _toggle(u),
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
                            subtitle: u.disabled ? const Text('Gesperrt') : null,
                            titleAlignment: ListTileTitleAlignment.center,
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
