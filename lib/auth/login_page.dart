import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
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

    // Close keyboard before doing anything else (helps web/mobile viewport reset).
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final tokens = await widget.api.login(
        username: _username.text.trim(),
        password: _password.text,
      );

      await widget.authStore.setTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );

      if (!mounted) return;
      context.go('/home');
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login fehlgeschlagen: $e')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context); // keyboard insets
    final mq = MediaQuery.of(context);

    return Scaffold(
      // Keep this true; we handle padding + scroll to avoid "stuck" white space.
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                // Important for web/mobile keyboard: adjust when insets change
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + viewInsets.bottom,
                ),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  // Ensures Center-like behavior without fighting the keyboard
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
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
                                    onFieldSubmitted: (_) {
                                      _passwordFocus.requestFocus();
                                    },
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
                                    onFieldSubmitted: (_) {
                                      // Enter submits on desktop keyboards and most mobile IMEs.
                                      _login();
                                    },
                                    autofillHints: const [AutofillHints.password],
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
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                          : const Icon(Icons.login_rounded),
                                      label: Text(_loading ? 'Anmelden…' : 'Anmelden'),
                                    ),
                                  ),

                                  // Optional: small spacer to avoid edge cases on very short viewports
                                  SizedBox(height: mq.size.height < 500 ? 8 : 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
