import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../common/member_picker_settings.dart';
import '../../models/dtos.dart';
import '../../models/member_status.dart';

class MemberPickerSheet extends StatefulWidget {
  final ApiClient api;
  final Set<String> initialSelectedIds;

  const MemberPickerSheet({
    super.key,
    required this.api,
    required this.initialSelectedIds,
  });

  @override
  State<MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<MemberPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  bool _hidePhilister = false;
  List<UserPickerDto> _users = const [];
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedIds};
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({String? query}) async {
    setState(() => _loading = true);

    try {
      final hidePhilister = await MemberPickerSettings.hidePhilister();
      final users = await widget.api.pickerUsers(query: query);

      final filtered = users.where((u) {
        return MemberStatuses.shouldShowInPicker(
          memberStatus: u.memberStatus,
          hidePhilister: hidePhilister,
          forceShow: _selected.contains(u.id),
        );
      }).toList(growable: false);

      filtered.sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ),
      );

      if (!mounted) return;
      setState(() {
        _hidePhilister = hidePhilister;
        _users = filtered;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mitglieder laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _load(query: v.trim().isEmpty ? null : v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _hidePhilister
        ? 'Philister werden ausgeblendet'
        : 'Alle Mitglieder werden angezeigt';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mitglieder auswählen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: const Text('Fertig'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                labelText: 'Suchen',
              ),
            ),
            const SizedBox(height: 12),
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
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(u.id);
                        } else {
                          _selected.remove(u.id);
                        }
                      });
                    },
                    title: Text(
                      MemberStatuses.pickerDisplayName(
                        displayName: u.displayName,
                        memberStatus: u.memberStatus,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}