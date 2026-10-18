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

/// Which field a validation message belongs under.
enum _Field { fullName, email, password }

/// The shortest password the server accepts on register and on reset
/// (`MIN_PASSWORD_LENGTH` in its auth routes).
const _minPasswordLength = 8;

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();

  bool _registering = false;
  bool _busy = false;

  /// Starts hidden, as any password field does; the eye reveals it so a
  /// mistyped character can be found without retyping the whole thing.
  bool _obscurePassword = true;

  /// A message from the server or Google, about the request as a whole.
  String? _error;

  /// A validation message, shown under the field it is about so the user
  /// does not have to work out which box to fix.
  ({_Field field, String message})? _fieldError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  /// Returns the first problem and the field it is about, or null when the
  /// form is usable.
  ({_Field field, String message})? _validate() {
    if (_email.text.trim().isEmpty) {
      return (field: _Field.email, message: 'Enter your email.');
    }
    if (!_email.text.contains('@')) {
      return (
        field: _Field.email,
        message: 'That does not look like an email.',
      );
    }
    if (_password.text.isEmpty) {
      return (field: _Field.password, message: 'Enter your password.');
    }
    // On sign up the server turns a short one down, but only after a round
    // trip and in a message about the whole form. Never on sign in: an
    // account made before the rule must still get in.
    if (_registering && _password.text.length < _minPasswordLength) {
      return (
        field: _Field.password,
        message: 'Use at least $_minPasswordLength characters.',
      );
    }
    if (_registering && _fullName.text.trim().isEmpty) {
      return (field: _Field.fullName, message: 'Enter your name.');
    }
    return null;
  }

  String? _errorFor(_Field field) =>
      _fieldError?.field == field ? _fieldError!.message : null;

  /// Drops a field's message once the user edits that field: the message
  /// described the old text, and leaving it up would claim the new text is
  /// wrong too.
  void _clearErrorFor(_Field field) {
    if (_fieldError?.field == field) setState(() => _fieldError = null);
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });

    try {
      final idToken = await ref.read(googleSignInGatewayProvider).idToken();
      if (!mounted) return;
      // A cancelled dialog is a decision, not a failure. Leave the screen
      // exactly as it was so the user can pick another way in.
      if (idToken == null) return;

      final user = await ref
          .read(authRepositoryProvider)
          .signInWithGoogle(idToken);
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
      setState(() {
        _fieldError = problem;
        _error = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
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
        _pushCheckEmail(email, password, sendCodeOnOpen: false);
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
        // (enter the emailed code), so a generic error message would only
        // leave the user guessing what the code means. The code from back
        // then has most likely expired, so the screen asks for a fresh one.
        _pushCheckEmail(email, password, sendCodeOnOpen: true);
      } else {
        // The fields keep their text on purpose — a wrong password should
        // cost one character, not the whole form.
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pushCheckEmail(
    String email,
    String password, {
    required bool sendCodeOnOpen,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckEmailScreen(
          email: email,
          password: password,
          sendCodeOnOpen: sendCodeOnOpen,
        ),
      ),
    );
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ForgotPasswordScreen()),
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
                // One group so a password manager fills the email and the
                // password together, and offers to save them on success.
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_registering) ...[
                        _LabeledField(
                          label: 'Full name',
                          error: _errorFor(_Field.fullName),
                          field: FsField(
                            fieldKey: const Key('fullName'),
                            controller: _fullName,
                            hint: 'Juan Dela Cruz',
                            icon: Icons.person_outline,
                            keyboardType: TextInputType.name,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            onChanged: (_) => _clearErrorFor(_Field.fullName),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _LabeledField(
                        label: 'Email',
                        error: _errorFor(_Field.email),
                        field: FsField(
                          fieldKey: const Key('email'),
                          controller: _email,
                          hint: 'you@email.com',
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          onChanged: (_) => _clearErrorFor(_Field.email),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: 'Password',
                        // The same minimum the server enforces on register
                        // and on reset, stated before the user picks one
                        // rather than after the server turns it down.
                        helper: _registering
                            ? 'At least $_minPasswordLength characters'
                            : null,
                        error: _errorFor(_Field.password),
                        field: FsField(
                          fieldKey: const Key('password'),
                          controller: _password,
                          hint: _registering
                              ? 'Create a password'
                              : 'Your password',
                          icon: Icons.lock_outline,
                          obscure: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          // A new password lets the manager suggest a strong
                          // one; a current one lets it fill the saved one.
                          autofillHints: [
                            _registering
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onChanged: (_) => _clearErrorFor(_Field.password),
                          trailing: IconButton(
                            key: const Key('togglePassword'),
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: t.text2,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                            _fieldError = null;
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
                              color: t.accentText,
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
        // Shrinks rather than overflowing on a narrow phone at large text: a
        // wordmark cut to an ellipsis would no longer be the name.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'FitSync',
              maxLines: 1,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.84,
                color: t.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A field with its name above it and its helper or error text below.
///
/// The placeholder alone vanishes as soon as the user types, taking the
/// field's name with it. The visible texts are hidden from screen readers and
/// given to the field as its label and hint instead, so the field is announced
/// with its name and any message about it. Not [MergeSemantics]: that would
/// also swallow the eye button inside the password field, leaving it
/// unreachable by TalkBack and VoiceOver.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.field,
    this.helper,
    this.error,
  });

  final String label;
  final Widget field;
  final String? helper;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    final hint = [error, helper].nonNulls.join('. ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.text2,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(label: label, hint: hint.isEmpty ? null : hint, child: field),
        if (helper != null) ...[
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(
              helper!,
              style: TextStyle(fontSize: 12, color: t.text2),
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(error!, style: TextStyle(fontSize: 12.5, color: t.red)),
          ),
        ],
      ],
    );
  }
}
