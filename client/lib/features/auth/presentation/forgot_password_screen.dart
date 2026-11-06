import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/auth_user.dart';
import 'auth_controller.dart';
import 'code_entry.dart';

const _sentMessage = "If that address has an account, we've sent a code.";
const _resentMessage =
    'If that address has an account, a new code is on its way.';

/// Password reset in two steps on one screen: an email, then the emailed
/// 6-digit code with a new password, ending signed in.
///
/// The server answers every code request the same way -- a 202, whatever the
/// address -- so this screen can never be used to learn who has an account.
/// It must not undo that: step 1 moves on to step 2 with the same message
/// whatever the server answered. The one exception is a request that never
/// reached it (NETWORK_ERROR): no answer came back, so saying so reveals
/// nothing about the address, and claiming a code was sent would leave the
/// user waiting for an email nobody asked for.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// What was already typed into sign-in's email field, so the user does not
  /// have to type it again. Empty when there was nothing.
  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

/// Which request is on its way, so only the button that sent it spins. The
/// other is disabled without a spinner: one request at a time.
enum _Pending { none, sendCode, reset }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _onCodeStep = false;
  _Pending _pending = _Pending.none;
  bool get _busy => _pending != _Pending.none;

  /// Starts hidden, as on sign-in; the eye shows it. A successful reset
  /// signs in with exactly what was typed, so a typo would otherwise become
  /// the password without the user ever seeing it.
  bool _obscurePassword = true;

  /// Set once the server accepts the reset. From then on the button only
  /// retries the sign-in: the code is spent.
  bool _resetDone = false;

  /// The last outcome, and whether it went wrong: an error is drawn as one
  /// (red, with an icon) so it cannot be mistaken for "we've sent a code".
  ({String text, bool isError})? _message;

  void _showError(String text) =>
      setState(() => _message = (text: text, isError: true));

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Step 1's button and step 2's "Send a new code".
  Future<void> _sendCode() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!_onCodeStep) {
      if (email.isEmpty) {
        _showError('Enter your email.');
        return;
      }
      if (!email.contains('@')) {
        _showError('That does not look like an email.');
        return;
      }
    }
    final repo = ref.read(authRepositoryProvider);
    final resending = _onCodeStep;
    setState(() {
      _pending = _Pending.sendCode;
      _message = null;
    });

    try {
      await repo.requestPasswordReset(email);
    } on ApiException catch (error) {
      if (error.code == 'NETWORK_ERROR') {
        // Nothing was sent: stay where the user is and say why.
        if (mounted) {
          setState(() => _pending = _Pending.none);
          _showError(userMessage(error));
        }
        return;
      }
      // Any answer the server did give is swallowed -- see the class doc.
    } catch (_) {
      // Swallowed too, for the same reason.
    }
    if (!mounted) return;
    setState(() {
      _pending = _Pending.none;
      _onCodeStep = true;
      _message = (
        text: resending ? _resentMessage : _sentMessage,
        isError: false,
      );
    });
  }

  /// Back to step 1 with the address still typed, to correct it. The code
  /// and password belong to the old address, so they go.
  void _changeEmail() => setState(() {
    _onCodeStep = false;
    _message = null;
    _code.clear();
    _password.clear();
  });

  Future<void> _reset() async {
    if (_busy) return;
    if (!_resetDone) {
      if (_code.text.length != 6) {
        _showError('Enter the 6-digit code from the email.');
        return;
      }
      if (_password.text.length < 8) {
        _showError('Use at least 8 characters for your new password.');
        return;
      }
    }
    // Read before any await: the screen can be gone by the time one resolves.
    final repo = ref.read(authRepositoryProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _pending = _Pending.reset;
      _message = null;
    });

    // No `mounted` check here: repo.login has already stored the session
    // token, so finishing onAuthenticated keeps the app consistent with
    // that stored session even if this screen was closed mid-flight.
    // Skipping it would leave the UI signed out while holding a valid
    // token.
    void signedIn(AuthUser user) {
      navigator.popUntil((route) => route.isFirst);
      controller.onAuthenticated(user);
      showSignedInBanner(messenger, resetSignInMessage);
    }

    try {
      if (!_resetDone) {
        await repo.resetPassword(
          email: email,
          code: _code.text,
          password: password,
        );
        // Set the field regardless of mounted; only the rebuild is
        // conditional, so a catch reached after the screen is gone still
        // sees the code as spent and asks to retry the sign-in, not resend it.
        _resetDone = true;
        if (mounted) setState(() {});
      }
      signedIn(await repo.login(email, password));
    } on ApiException catch (error) {
      if (!_resetDone && error.code == 'CODE_INVALID') {
        // Perhaps the reset went through and only the reply was lost: then
        // the new password already works.
        final user = await signInAfterRejectedCode(repo, email, password);
        if (user != null) {
          signedIn(user);
          return;
        }
      }
      if (!mounted) return;
      if (_resetDone) {
        // Good news, drawn in neutral text rather than as an error even
        // though the sign-in after it failed.
        setState(
          () => _message = (
            text: 'Your password is reset. Tap to sign in.',
            isError: false,
          ),
        );
        return;
      }
      _showError(
        error.code == 'CODE_INVALID' ? wrongCodeMessage : userMessage(error),
      );
    } finally {
      if (mounted) setState(() => _pending = _Pending.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    // Both kinds are live regions, so a screen reader says the outcome of
    // Send code or Reset password as it appears.
    final message = switch (_message) {
      null => const <Widget>[],
      (:final text, isError: true) => [
        const SizedBox(height: 14),
        FsErrorLine(text, key: const Key('message')),
      ],
      (:final text, isError: false) => [
        const SizedBox(height: 14),
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            text,
            key: const Key('message'),
            style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
          ),
        ),
      ],
    };

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: !_onCodeStep
                ? [
                    Text(
                      'Reset your\npassword.',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Enter your email and we'll send a 6-digit code to "
                      'reset your password.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: t.text2,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FsLabeledField(
                      label: 'Email',
                      field: FsField(
                        fieldKey: const Key('email'),
                        controller: _email,
                        hint: 'you@email.com',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendCode(),
                      ),
                    ),
                    ...message,
                    const SizedBox(height: 18),
                    FsButton(
                      key: const Key('submit'),
                      label: 'Send code',
                      busy: _pending == _Pending.sendCode,
                      onPressed: _busy ? null : _sendCode,
                    ),
                  ]
                : [
                    Text(
                      'Enter your code',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Enter the 6-digit code we emailed to '
                      '${_email.text.trim()} and choose a new password.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: t.text2,
                        height: 1.5,
                      ),
                    ),
                    // A typo in the address shows here, under the sentence
                    // that names it; Back would leave the whole reset. The
                    // button's 48 dp brings room of its own above and below.
                    if (!_resetDone) ...[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const Key('changeEmail'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _busy ? null : _changeEmail,
                          child: const Text('Use a different email'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else
                      const SizedBox(height: 22),
                    if (!_resetDone) ...[
                      FsLabeledField(
                        label: 'Code',
                        field: CodeField(controller: _code),
                      ),
                      const SizedBox(height: 14),
                      FsLabeledField(
                        label: 'New password',
                        // The same minimum the server enforces, kept on
                        // screen: a placeholder would vanish at the first
                        // keystroke.
                        helper: 'At least 8 characters',
                        field: FsField(
                          fieldKey: const Key('newPassword'),
                          controller: _password,
                          hint: 'Choose a new password',
                          icon: Icons.lock_outline,
                          obscure: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          trailing: IconButton(
                            key: const Key('toggleNewPassword'),
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
                    ...message,
                    const SizedBox(height: 18),
                    FsButton(
                      key: const Key('reset'),
                      label: _resetDone ? 'Sign in' : 'Reset password',
                      busy: _pending == _Pending.reset,
                      onPressed: _busy ? null : _reset,
                    ),
                    if (!_resetDone) ...[
                      const SizedBox(height: 10),
                      FsButton(
                        key: const Key('resend'),
                        label: 'Send a new code',
                        kind: FsButtonKind.secondary,
                        busy: _pending == _Pending.sendCode,
                        onPressed: _busy ? null : _sendCode,
                      ),
                    ],
                  ],
          ),
        ),
      ),
    );
  }
}
