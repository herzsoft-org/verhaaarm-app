import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class PeriodFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String? periodId;

  const PeriodFormPage({super.key, required this.api, required this.authStore, this.periodId});

  @override
  State<PeriodFormPage> createState() => _PeriodFormPageState();
}

class _PeriodFormPageState extends State<PeriodFormPage> {
  bool _loading = true;
  bool _saving = false;

  final _semesterCtrl = TextEditingController();
  final _startAtIsoCtrl = TextEditingController(); // stores ISO (UTC) for backend
  final _endAtIsoCtrl = TextEditingController(); // stores ISO (UTC) for backend

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _semesterCtrl.dispose();
    _startAtIsoCtrl.dispose();
    _endAtIsoCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseIso(String? iso) {
    final s = (iso ?? '').trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _displayForIso(String iso) => Format.dateTimeShort(iso);

  Future<void> _pickDateTime({
    required TextEditingController targetIsoCtrl,
    DateTime? initial,
  }) async {
    final now = DateTime.now();
    final init = initial ?? _parseIso(targetIsoCtrl.text) ?? now.add(const Duration(hours: 2));

    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (time == null) return;

    if (!mounted) return;

    final pickedLocal = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final pickedUtc = pickedLocal.toUtc();

    setState(() {
      targetIsoCtrl.text = pickedUtc.toIso8601String();
    });
  }

  Widget _pickerField({
    required String label,
    required String valueText,
    required VoidCallback onPick,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: InkWell(
        onTap: _saving ? null : onPick,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text(valueText.isEmpty ? 'Auswählen…' : valueText)),
              const Icon(Icons.calendar_month_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!Roles.canManagePeriods(roles)) {
        if (!mounted) return;
        context.go('/home');
        return;
      }

      if (widget.periodId != null) {
        final p = await widget.api.getPeriod(widget.periodId!);
        _semesterCtrl.text = p.semester;
        _startAtIsoCtrl.text = p.startAt;
        _endAtIsoCtrl.text = p.endAt;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Laden fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final semester = _semesterCtrl.text.trim();
    final startAt = _startAtIsoCtrl.text.trim();
    final endAt = _endAtIsoCtrl.text.trim();

    if (semester.isEmpty || startAt.isEmpty || endAt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semester, Start und Ende sind Pflichtfelder.')),
      );
      return;
    }

    final start = DateTime.tryParse(startAt);
    final end = DateTime.tryParse(endAt);
    if (start == null || end == null || !end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ende muss nach Start liegen.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.periodId == null) {
        final req = CreateConventPeriodRequest(
          semester: semester,
          startAt: startAt,
          endAt: endAt,
        );
        await widget.api.createPeriod(req);
      } else {
        final req = UpdateConventPeriodRequest(
          semester: semester,
          startAt: startAt,
          endAt: endAt,
        );
        await widget.api.updatePeriod(widget.periodId!, req);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.periodId != null;

    final startIso = _startAtIsoCtrl.text.trim();
    final endIso = _endAtIsoCtrl.text.trim();

    return AppScaffold(
      title: isEdit ? 'Periode bearbeiten' : 'Periode erstellen',
      actions: [
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: (_loading || _saving) ? null : _save,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _semesterCtrl,
            decoration: const InputDecoration(
              labelText: 'Semester',
              hintText: 'WS25/26 oder SS25',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          _pickerField(
            label: 'Start',
            valueText: startIso.isEmpty ? '' : _displayForIso(startIso),
            onPick: () => _pickDateTime(targetIsoCtrl: _startAtIsoCtrl),
          ),
          const SizedBox(height: 12),

          _pickerField(
            label: 'Ende',
            valueText: endIso.isEmpty ? '' : _displayForIso(endIso),
            onPick: () => _pickDateTime(
              targetIsoCtrl: _endAtIsoCtrl,
              initial: _parseIso(_startAtIsoCtrl.text),
            ),
          ),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_saving) ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Speichert…' : 'Speichern'),
          ),
        ],
      ),
    );
  }
}
