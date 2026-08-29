import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../domain/auth_user.dart';
import 'auth_controller.dart';

/// One screen for both signing in and registering.
///
/// Register takes the same two fields plus a name, so splitting them into two
/// screens would duplicate the whole form and both error paths for one extra
/// input. Per the design: no Apple button, and no "Forgot password?" — there
/// is no password reset in this milestone, and offering one that does nothing
/// is worse than not offering it.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  /// Returns the message to show, or null when the form is usable.
  String? _validate() {
    if (_email.text.trim().isEmpty) return 'Enter your email.';
    if (!_email.text.contains('@')) return 'That does not look like an email.';
    if (_password.text.isEmpty) return 'Enter your password.';
    if (_registering && _fullName.text.trim().isEmpty) {
      return 'Enter your name.';
    }
    return null;
  }

  Future<void> _submit() async {
    // Guard here as well as on the button: a tap already in flight when the
    // widget rebuilds must not start a second request.
    if (_busy) return;

    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      final AuthUser user = _registering
          ? await repo.register(
              email: _email.text.trim(),
              password: _password.text,
              fullName: _fullName.text.trim(),
            )
          : await repo.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      // The token is already stored by the repository, so the shell can move
      // on without a second round trip.
      ref.read(authControllerProvider.notifier).onAuthenticated(user);
    } on ApiException catch (error) {
      if (!mounted) return;
      // The fields keep their text on purpose — a wrong password should cost
      // one character, not the whole form.
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _registering ? 'Create your account' : 'Welcome back',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_registering) ...[
                  TextField(
                    key: const Key('fullName'),
                    controller: _fullName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  // Inline rather than a SnackBar: a snack bar times out, and
                  // an error the user needs in order to fix their input should
                  // stay on screen until they do.
                  Text(
                    _error!,
                    key: const Key('error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_registering ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('google'),
                  // Wired in Task 11, once the Google OAuth client exists.
                  // Disabled rather than absent so the button's place in the
                  // layout is already settled.
                  onPressed: null,
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text('Continue with Google (coming soon)'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('toggleMode'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _registering = !_registering;
                            _error = null;
                          }),
                  child: Text(
                    _registering
                        ? 'Already have an account? Sign in'
                        : 'New here? Create account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
