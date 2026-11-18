import 'package:flutter/material.dart';

import '../state/quiz_controller.dart';

class SignInView extends StatefulWidget {
  const SignInView({super.key, required this.controller});
  final QuizController controller;

  @override
  State<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    widget.controller.signIn(_email.text.trim(), _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.science_outlined,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Science Signal',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('Sign in with your test account to play.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                ),
                if (c.phase == Phase.authError && c.authMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(c.authMessage!,
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer)),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: c.signingIn ? null : _submit,
                  icon: c.signingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(c.signingIn ? 'Signing in…' : 'Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
