import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../data/google_sign_in_gateway.dart';
import 'auth_controller.dart';
import 'auth_text_link.dart';
import 'check_email_screen.dart';
import 'editable_under.dart';
import 'forgot_password_screen.dart';
import 'google_g_mark.dart';

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

/// Which request is on its way, so only the button that started it spins
/// (and is announced as loading). The others are disabled without one: one
/// request at a time.
enum _Pending { none, email, google }

/// The shortest password the server accepts on register and on reset
/// (`MIN_PASSWORD_LENGTH` in its auth routes).
const _minPasswordLength = 8;

/// When Google itself could not sign the user in. Names the other way in,
/// since retrying may not help on a phone without Play Services.
const _googleFailedMessage =
    "Couldn't sign in with Google. Try again, or use your email and password.";

/// Registering an address that already has an account. The server's own
/// words ("already registered") leave the user stuck in Create account mode,
/// so this says what to do, and a link under it does it.
const _emailTakenMessage = 'That email already has an account.';

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();

  bool _registering = false;
  _Pending _pending = _Pending.none;
  bool get _busy => _pending != _Pending.none;

  /// Starts hidden, as any password field does; the eye reveals it so a
  /// mistyped character can be found without retyping the whole thing.
  bool _obscurePassword = true;

  /// A message from the server or Google, about the request as a whole.
  String? _error;

  /// True only while [_error] says the email is taken on Create account, so
  /// the line offers "Sign in instead". Set with the message by [_setError],
  /// never inferred from its words.
  bool _emailTaken = false;

  void _setError(String? message, {bool emailTaken = false}) {
    _error = message;
    _emailTaken = emailTaken;
  }

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
  /// form is usable. Checked in the order the fields are drawn, so the one
  /// named is the first a user meets going down the form.
  ({_Field field, String message})? _validate() {
    if (_registering && _fullName.text.trim().isEmpty) {
      return (field: _Field.fullName, message: 'Enter your name.');
    }
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
    return null;
  }

  /// One per field, around its [FsLabeledField], so a failed check can put
  /// the cursor in the field it is about.
  final _fieldKeys = {for (final field in _Field.values) field: GlobalKey()};

  /// Moves the cursor -- and a screen reader, which then reads the field's
  /// name and the message now in its hint -- to [field]. Otherwise nothing
  /// is heard after Sign in, and a failed check sounds like a hang.
  ///
  /// When [field] already has focus (typed in last: a phone does not unfocus
  /// a field on an outside tap) focus cannot move, so nothing would be read.
  /// [message] is announced instead -- only then, so it is never said twice.
  void _focus(_Field field, String message) {
    final target = editableUnder(_fieldKeys[field]!);
    if (target == null) return;
    if (target.widget.focusNode.hasFocus) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
      return;
    }
    target.requestKeyboard();
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
      _pending = _Pending.google;
      _setError(null);
      _fieldError = null;
    });

    try {
      final result = await ref.read(googleSignInGatewayProvider).signIn();
      if (!mounted) return;
      final String idToken;
      switch (result) {
        case GoogleSignInToken(idToken: final token):
          idToken = token;
        // A cancelled dialog is a decision, not a failure. Leave the screen
        // exactly as it was so the user can pick another way in.
        case GoogleSignInCancelled():
          return;
        case GoogleSignInFailed(:final cause):
          // Never shown -- the message names another way in instead -- but
          // without it a broken build gives no clue why Google failed.
          // Debug builds only: debugPrint still prints in release, and the
          // phone's log is no place for a sign-in failure's details.
          if (kDebugMode) debugPrint('Google sign-in failed: $cause');
          setState(() => _setError(_googleFailedMessage));
          return;
      }

      final user = await ref
          .read(authRepositoryProvider)
          .signInWithGoogle(idToken);
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).onAuthenticated(user);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _setError(userMessage(error)));
    } catch (error) {
      // Anything else, so a tap never just stops the spinner and says
      // nothing: this is the only way in without a password.
      if (kDebugMode) debugPrint('Google sign-in failed: $error');
      if (!mounted) return;
      setState(() => _setError(_googleFailedMessage));
    } finally {
      if (mounted) setState(() => _pending = _Pending.none);
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
        _setError(null);
      });
      _focus(problem.field, problem.message);
      return;
    }

    setState(() {
      _pending = _Pending.email;
      _setError(null);
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
      } else if (_registering && error.code == 'EMAIL_TAKEN') {
        setState(() => _setError(_emailTakenMessage, emailTaken: true));
      } else {
        // The fields keep their text on purpose — a wrong password should
        // cost one character, not the whole form.
        setState(() => _setError(userMessage(error)));
      }
    } finally {
      if (mounted) setState(() => _pending = _Pending.none);
    }
  }

  /// Switches between signing in and creating an account. The email and
  /// password stay: they are the same two fields in both modes.
  void _setRegistering(bool registering) => setState(() {
    _registering = registering;
    _setError(null);
    _fieldError = null;
  });

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
      MaterialPageRoute<void>(
        builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final accountDeleted =
        ref.watch(authControllerProvider).value?.reason ==
        SignOutReason.accountDeleted;

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
                if (accountDeleted) ...[
                  const SizedBox(height: 18),
                  const _AccountDeletedNote(),
                ],
                const SizedBox(height: 30),
                // One group so a password manager fills the email and the
                // password together, and offers to save them on success.
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_registering) ...[
                        FsLabeledField(
                          key: _fieldKeys[_Field.fullName],
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
                      FsLabeledField(
                        key: _fieldKeys[_Field.email],
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
                      FsLabeledField(
                        key: _fieldKeys[_Field.password],
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
                // The link's 48dp target brings its own space above the
                // words, which is why there is no gap before it.
                if (!_registering)
                  Align(
                    alignment: Alignment.centerRight,
                    child: AuthTextLink(
                      key: const Key('forgotPassword'),
                      onTap: _busy ? null : _openForgotPassword,
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(fontSize: 11.5, color: t.text2),
                      ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  // Inline rather than a SnackBar: a snack bar times out, and
                  // an error the user needs in order to fix their input should
                  // stay on screen until they do.
                  // A live region, so a screen reader says it as it
                  // appears: otherwise a failed sign-in sounds like a hang.
                  FsErrorLine(_error!, key: const Key('error')),
                  if (_emailTaken)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AuthTextLink(
                        key: const Key('signInInstead'),
                        onTap: _busy ? null : () => _setRegistering(false),
                        child: Text(
                          'Sign in instead',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: t.accentText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                FsButton(
                  key: const Key('submit'),
                  label: _registering ? 'Create account' : 'Sign in',
                  busy: _pending == _Pending.email,
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
                  // Google's own colour G, which its sign-in branding
                  // requires, in place of the prototype's one-colour G.
                  icon: const GoogleGMark(),
                  busy: _pending == _Pending.google,
                  onPressed: _busy ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 8),
                Center(
                  child: AuthTextLink(
                    key: const Key('toggleMode'),
                    onTap: _busy ? null : () => _setRegistering(!_registering),
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

/// Why the user is back on sign-in after Delete account: the account is
/// gone, and without a word the screen looks like an unexplained sign-out.
/// Stays until they sign in, unlike a SnackBar that can time out unseen. A
/// live region, so a screen reader says it as the screen appears.
class _AccountDeletedNote extends StatelessWidget {
  const _AccountDeletedNote();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      key: const Key('signIn.accountDeleted'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: t.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your account was deleted.',
                style: TextStyle(fontSize: 13, height: 1.4, color: t.text),
              ),
            ),
          ],
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
          alignment: Alignment.center,
          // The prototype's FitBlades at two thirds of the tile.
          child: CustomPaint(
            key: const Key('logo.blades'),
            size: const Size.square(22),
            painter: _BladesPainter(t.onAccent),
          ),
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

/// FitSync's mark, the prototype's `FitBlades` (kit.jsx): one blade drawn
/// three times, turned 0, 120 and 240 degrees about the centre, each fainter
/// than the last.
class _BladesPainter extends CustomPainter {
  const _BladesPainter(this.color);

  final Color color;

  static const _opacities = [1.0, 0.6, 0.32];

  @override
  void paint(Canvas canvas, Size size) {
    // The SVG's 100-unit box, scaled to [size].
    final scale = size.shortestSide / 100;
    final blade = Path()
      ..moveTo(50, 50)
      ..cubicTo(52, 30, 62, 18, 80, 22)
      ..cubicTo(70, 38, 66, 46, 50, 50)
      ..close();

    canvas
      ..save()
      ..scale(scale);
    for (var i = 0; i < _opacities.length; i++) {
      canvas.drawPath(
        blade,
        Paint()..color = color.withValues(alpha: _opacities[i]),
      );
      canvas
        ..translate(50, 50)
        ..rotate(2 * math.pi / 3)
        ..translate(-50, -50);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BladesPainter old) => old.color != color;
}
