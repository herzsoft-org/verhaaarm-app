import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../common/api_error_text.dart';
import '../common/settings/app_settings_store.dart';
import 'auth_store.dart';

class LoginPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const LoginPage({super.key, required this.api, required this.authStore});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading = false;
  String? _loginError;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;

    FocusManager.instance.primaryFocus?.unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _loginError = null;
    });

    try {
      final tokens = await widget.api.login(
        username: _username.text.trim(),
        password: _password.text,
      );

      await widget.authStore.setTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        sessionId: tokens.sessionId,
      );

      await AppSettingsStore.I.syncWithBackend(widget.api);

      try {
        await widget.authStore.refreshMe(widget.api, force: true);
      } catch (_) {
        // Login still succeeded; token roles remain fallback.
      }

      if (!mounted) return;
      context.go('/home');
    } on DioException catch (e) {
      if (!mounted) return;

      String message;
      if (e.response?.statusCode == 401) {
        message = 'Benutzername oder Passwort ist falsch.';
      } else {
        message = userFriendlyApiError(e, fallback: 'Login fehlgeschlagen.');
      }

      setState(() => _loginError = message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loginError = 'Login fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IMPORTANT: keep default behavior (true). Do not manually pad with viewInsets.
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          // Your app already has global bottom SafeArea; avoid double-bottom padding.
          top: true,
          bottom: false,
          left: false,
          right: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Verhåårm',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _username,
                              focusNode: _usernameFocus,
                              decoration: const InputDecoration(
                                labelText: 'Benutzername',
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Bitte Benutzername eingeben.'
                                  : null,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _passwordFocus.requestFocus(),
                              autofillHints: const [AutofillHints.username],
                            ),

                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _password,
                              focusNode: _passwordFocus,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Passwort',
                                prefixIcon: Icon(Icons.lock_rounded),
                              ),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Bitte Passwort eingeben.'
                                  : null,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _login(),
                              autofillHints: const [AutofillHints.password],
                            ),

                            const SizedBox(height: 12),

                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: _loginError == null
                                  ? const SizedBox.shrink()
                                  : Container(
                                key: const ValueKey('login-error'),
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _loginError!,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _loading ? null : _login,
                                icon: _loading
                                    ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                  _loading ? 'Anmelden…' : 'Anmelden',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}