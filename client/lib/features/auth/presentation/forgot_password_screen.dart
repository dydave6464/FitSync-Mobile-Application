import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
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
/// whatever happened, a network error included.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _onCodeStep = false;
  bool _busy = false;

  /// Set once the server accepts the reset. From then on the button only
  /// retries the sign-in: the code is spent.
  bool _resetDone = false;
  String? _message;

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
        setState(() => _message = 'Enter your email.');
        return;
      }
      if (!email.contains('@')) {
        setState(() => _message = 'That does not look like an email.');
        return;
      }
    }
    final repo = ref.read(authRepositoryProvider);
    final resending = _onCodeStep;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await repo.requestPasswordReset(email);
    } catch (_) {
      // Deliberately swallowed -- see the class doc.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _onCodeStep = true;
          _message = resending ? _resentMessage : _sentMessage;
        });
      }
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (!_resetDone) {
      if (_code.text.length != 6) {
        setState(() => _message = 'Enter the 6-digit code from the email.');
        return;
      }
      if (_password.text.length < 8) {
        setState(
          () => _message = 'Use at least 8 characters for your new password.',
        );
        return;
      }
    }
    // Read before any await: the screen can be gone by the time one resolves.
    final repo = ref.read(authRepositoryProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final navigator = Navigator.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _busy = true;
      _message = null;
    });

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
      final user = await repo.login(email, password);
      // No `mounted` check here: repo.login has already stored the session
      // token, so finishing onAuthenticated keeps the app consistent with
      // that stored session even if this screen was closed mid-flight.
      // Skipping it would leave the UI signed out while holding a valid
      // token.
      navigator.popUntil((route) => route.isFirst);
      controller.onAuthenticated(user);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _resetDone
            ? 'Your password is reset. Tap to sign in.'
            : (error.code == 'CODE_INVALID' ? wrongCodeMessage : error.message);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final message = _message == null
        ? const <Widget>[]
        : [
            const SizedBox(height: 14),
            Text(
              _message!,
              key: const Key('message'),
              style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
            ),
          ];

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
                    FsField(
                      fieldKey: const Key('email'),
                      controller: _email,
                      hint: 'you@email.com',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    ...message,
                    const SizedBox(height: 18),
                    FsButton(
                      key: const Key('submit'),
                      label: 'Send code',
                      busy: _busy,
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
                    const SizedBox(height: 22),
                    if (!_resetDone) ...[
                      CodeField(controller: _code),
                      const SizedBox(height: 12),
                      FsField(
                        fieldKey: const Key('newPassword'),
                        controller: _password,
                        hint: 'New password (8+ characters)',
                        icon: Icons.lock_outline,
                        obscure: true,
                        autofillHints: const [AutofillHints.newPassword],
                      ),
                    ],
                    ...message,
                    const SizedBox(height: 18),
                    FsButton(
                      key: const Key('reset'),
                      label: _resetDone ? 'Sign in' : 'Reset password',
                      busy: _busy,
                      onPressed: _busy ? null : _reset,
                    ),
                    if (!_resetDone) ...[
                      const SizedBox(height: 10),
                      FsButton(
                        key: const Key('resend'),
                        label: 'Send a new code',
                        kind: FsButtonKind.secondary,
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
