import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/settings/app_settings_store.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class LiveEventFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String? liveEventId;

  const LiveEventFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.liveEventId,
  });

  @override
  State<LiveEventFormPage> createState() => _LiveEventFormPageState();
}

class _LiveEventFormPageState extends State<LiveEventFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _place = TextEditingController();
  final _desc = TextEditingController();

  bool _loading = false;

  bool get _sendNotificationsOnlyToMe {
    return widget.authStore.currentRoles.contains(AppRole.admin) &&
        AppSettingsStore.I.devModeNotifyOnlyMe;
  }

  @override
  void initState() {
    super.initState();
    if (widget.liveEventId != null) _loadExisting();
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      // no GET /live-events/{id}? yes it exists
      final r = await widget.api.dio.get('/live-events/${widget.liveEventId}');
      final dto = LiveEventDto.fromJson(r.data as Map<String, dynamic>);

      _title.text = dto.title;
      _place.text = dto.place ?? '';
      _desc.text = dto.description ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Laden fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      if (widget.liveEventId == null) {
        await widget.api.createLiveEvent(
          CreateLiveEventRequest(
            title: _title.text.trim(),
            place: _place.text.trim(),
            description: _desc.text.trim(),
            notifyOnlyMe: _sendNotificationsOnlyToMe,
          ),
        );
      } else {
        await widget.api.updateLiveEvent(
          widget.liveEventId!,
          UpdateLiveEventRequest(
            title: _title.text.trim(),
            place: _place.text.trim(),
            description: _desc.text.trim(),
          ),
        );
      }

      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.liveEventId != null;
    final showDevModeNote = !isEdit && _sendNotificationsOnlyToMe;

    return AppScaffold(
      title: isEdit ? 'Live-Event bearbeiten' : 'Live-Event erstellen',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (showDevModeNote) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Dev-Modus aktiv: Benachrichtigungen werden nur an dich gesendet.',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: 'Titel',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Bitte Titel eingeben.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _place,
                      decoration: const InputDecoration(
                        labelText: 'Ort',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Bitte Ort eingeben.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _desc,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Beschreibung',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Bitte Beschreibung eingeben.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _save,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(_loading ? 'Speichern…' : 'Speichern'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
