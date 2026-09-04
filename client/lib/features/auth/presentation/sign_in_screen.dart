import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import 'auth_controller.dart';
import 'check_email_screen.dart';
import 'forgot_password_screen.dart';

/// One screen for both signing in and registering.
///
/// Register takes the same two fields plus a name, so splitting them into two
/// screens would duplicate the whole form and both error paths for one extra
/// input. Per the design: still no Apple button — the prototype shows one,
/// but there is no Apple sign-in on the server, and offering a control that
/// does nothing is worse than not offering it.
///
/// A successful registration and an `EMAIL_NOT_VERIFIED` login both push
/// [CheckEmailScreen] rather than proceeding further: under the hard
/// verification gate neither leaves the caller with a session.
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

  Future<void> _signInWithGoogle() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final idToken = await ref.read(googleSignInGatewayProvider).idToken();
      if (!mounted) return;
      // A cancelled dialog is a decision, not a failure. Leave the screen
      // exactly as it was so the user can pick another way in.
      if (idToken == null) return;

      final user = await ref.read(authRepositoryProvider).signInWithGoogle(idToken);
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).onAuthenticated(user);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

    final email = _email.text.trim();
    final password = _password.text;

    try {
      final repo = ref.read(authRepositoryProvider);
      if (_registering) {
        await repo.register(
          email: email,
          password: password,
          fullName: _fullName.text.trim(),
        );
        if (!mounted) return;
        // Registration returns no token any more — the account exists but
        // cannot sign in until the address is verified — so there is no
        // user to hand the controller. Send the way forward instead.
        _pushCheckEmail(email, password);
      } else {
        final user = await repo.login(email, password);
        if (!mounted) return;
        // The token is already stored by the repository, so the shell can
        // move on without a second round trip.
        ref.read(authControllerProvider.notifier).onAuthenticated(user);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'EMAIL_NOT_VERIFIED') {
        // Same screen as a fresh registration: the way forward is identical
        // (open the email, verify, come back), so a generic error message
        // would only leave the user guessing what the code means.
        _pushCheckEmail(email, password);
      } else {
        // The fields keep their text on purpose — a wrong password should
        // cost one character, not the whole form.
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pushCheckEmail(String email, String password) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckEmailScreen(email: email, password: password),
      ),
    );
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ForgotPasswordScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Logo(),
                const SizedBox(height: 26),
                Text(
                  _registering
                      ? 'Create your\naccount.'
                      : 'Train smarter,\nrecover safer.',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Personalized workouts, recovery insight, and '
                  'Filipino-context nutrition — built for your goals.',
                  style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
                ),
                const SizedBox(height: 30),
                if (_registering) ...[
                  FsField(
                    fieldKey: const Key('fullName'),
                    controller: _fullName,
                    hint: 'Full name',
                    icon: Icons.person_outline,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 8),
                ],
                FsField(
                  fieldKey: const Key('email'),
                  controller: _email,
                  hint: 'you@email.com',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                FsField(
                  fieldKey: const Key('password'),
                  controller: _password,
                  hint: 'Password',
                  icon: Icons.lock_outline,
                  obscure: true,
                ),
                // Only in sign-in mode, matching the prototype: there is no
                // password to reset for an account that does not exist yet.
                if (!_registering) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      key: const Key('forgotPassword'),
                      onTap: _busy ? null : _openForgotPassword,
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(fontSize: 11.5, color: t.text2),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  // Inline rather than a SnackBar: a snack bar times out, and
                  // an error the user needs in order to fix their input should
                  // stay on screen until they do.
                  Text(
                    _error!,
                    key: const Key('error'),
                    style: TextStyle(fontSize: 12.5, color: t.red),
                  ),
                ],
                const SizedBox(height: 18),
                FsButton(
                  key: const Key('submit'),
                  label: _registering ? 'Create account' : 'Sign in',
                  busy: _busy,
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Divider(color: t.line, height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontFamily: fsMonoFamily,
                          fontSize: 11,
                          letterSpacing: 0.66,
                          color: t.text3,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: t.line, height: 1)),
                  ],
                ),
                const SizedBox(height: 18),
                FsButton(
                  key: const Key('google'),
                  label: 'Continue with Google',
                  kind: FsButtonKind.secondary,
                  small: true,
                  icon: const Icon(Icons.g_mobiledata),
                  onPressed: _busy ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 24),
                Center(
                  child: InkWell(
                    key: const Key('toggleMode'),
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _registering = !_registering;
                              _error = null;
                            }),
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 12.5, color: t.text2),
                        children: [
                          TextSpan(
                            text: _registering
                                ? 'Already have an account? '
                                : 'New here? ',
                          ),
                          TextSpan(
                            text: _registering ? 'Sign in' : 'Create account',
                            style: TextStyle(
                              color: t.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// The accent tile plus wordmark from the prototype's `Logo`.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.bolt, size: 22, color: t.onAccent),
        ),
        const SizedBox(width: 9),
        Text(
          'FitSync',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.84,
            color: t.text,
          ),
        ),
      ],
    );
  }
}
