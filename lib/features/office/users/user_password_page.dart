import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/widgets/app_scaffold.dart';

class UserPasswordPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;
  final String userId;

  const UserPasswordPage({super.key, required this.api, required this.authStore, required this.userId});

  @override
  State<UserPasswordPage> createState() => _UserPasswordPageState();
}

class _UserPasswordPageState extends State<UserPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await widget.api.setUserPassword(widget.userId, _pw1.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort gesetzt.')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Passwort setzen fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    if (!Roles.canManageUsers(roles)) {
      return AppScaffold(
        title: 'Passwort setzen',
        body: const Center(child: Text('Keine Berechtigung.')),
      );
    }

    return AppScaffold(
      title: 'Passwort setzen',
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
                      controller: _pw1,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Neues Passwort'),
                      validator: (v) {
                        if ((v ?? '').isEmpty) return 'Pflichtfeld';
                        if ((v ?? '').length < 6) return 'Mindestens 6 Zeichen';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pw2,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Wiederholen'),
                      validator: (v) {
                        if ((v ?? '').isEmpty) return 'Pflichtfeld';
                        if (v != _pw1.text) return 'Passwörter stimmen nicht überein';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Speichern'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
