import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class UserFormPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String? userId; // null => create

  const UserFormPage({
    super.key,
    required this.api,
    required this.authStore,
    this.userId,
  });

  @override
  State<UserFormPage> createState() => _UserFormPageState();
}

class _UserFormPageState extends State<UserFormPage> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;

  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _disabled = false;

  // Backend: exactly one role
  String _role = 'MEMBER';

  bool get _isEdit => widget.userId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = Roles.fromAccessToken(widget.authStore.accessToken);
      if (!Roles.canManageUsers(roles)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Berechtigung.')),
        );
        context.pop();
        return;
      }

      if (_isEdit) {
        final u = await widget.api.getUser(widget.userId!);
        _usernameCtrl.text = u.username;
        _displayNameCtrl.text = u.displayName;
        _disabled = u.disabled;
        _role = u.roles.isNotEmpty ? u.roles.first : 'MEMBER';
      } else {
        _disabled = false;
        _role = 'MEMBER';
      }

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laden fehlgeschlagen: $e')),
      );
      context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      if (_isEdit) {
        final req = UpdateUserRequest(
          displayName: _displayNameCtrl.text.trim(),
          disabled: _disabled,
          roles: [_role],
        );
        await widget.api.updateUser(widget.userId!, req);
      } else {
        final req = CreateUserRequest(
          username: _usernameCtrl.text.trim(),
          displayName: _displayNameCtrl.text.trim(),
          password: _passwordCtrl.text,
          roles: [_role],
        );
        await widget.api.createUser(req);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gespeichert.')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteHard() async {
    if (!_isEdit) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nutzer endgültig löschen?'),
        content: Text(
          'Dieser Nutzer wird hart gelöscht.\n\n'
              'Username: ${_usernameCtrl.text.trim()}\n'
              'Display Name: ${_displayNameCtrl.text.trim()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await widget.api.deleteUserHard(widget.userId!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nutzer gelöscht.')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Nutzer bearbeiten' : 'Nutzer anlegen';

    return AppScaffold(
      title: title,
      actions: [
        IconButton(
          tooltip: 'Speichern',
          icon: const Icon(Icons.save_rounded),
          onPressed: _loading ? null : _save,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameCtrl,
                      enabled: !_isEdit,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'mueller / peter-mueller',
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Pflichtfeld';
                        if (!_isEdit && s.length < 2) return 'Zu kurz';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _displayNameCtrl,
                      decoration: const InputDecoration(labelText: 'Display Name'),
                      validator: (v) =>
                      ((v ?? '').trim().isEmpty) ? 'Pflichtfeld' : null,
                    ),
                    if (!_isEdit) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        decoration:
                        const InputDecoration(labelText: 'Initiales Passwort'),
                        validator: (v) => ((v ?? '').isEmpty) ? 'Pflichtfeld' : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rolle', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text(
                      'Hinweis: Es muss immer mindestens einen ADMIN, SENIOR und HOUSEKEEPING geben.',
                    ),
                    const SizedBox(height: 12),
                    RadioGroup<String>(
                      groupValue: _role,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _role = v);
                      },
                      child: const Column(
                        children: [
                          _RoleRadio(label: 'ADMIN', value: 'ADMIN'),
                          _RoleRadio(label: 'SENIOR', value: 'SENIOR'),
                          _RoleRadio(label: 'HOUSEKEEPING', value: 'HOUSEKEEPING'),
                          _RoleRadio(label: 'TREASURER', value: 'TREASURER'),
                          _RoleRadio(label: 'MEMBER', value: 'MEMBER'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isEdit)
              Card(
                child: SwitchListTile(
                  title: const Text('Deaktiviert'),
                  subtitle: const Text('Deaktivierte Nutzer können sich nicht einloggen'),
                  value: _disabled,
                  onChanged: (v) => setState(() => _disabled = v),
                ),
              ),
            const SizedBox(height: 12),
            if (_isEdit)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      context.push('/office/users/${widget.userId}/password'),
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Passwort setzen'),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Speichern'),
              ),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _loading ? null : _deleteHard,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Nutzer löschen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleRadio extends StatelessWidget {
  final String label;
  final String value;

  const _RoleRadio({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      toggleable: false,
    );
  }
}
