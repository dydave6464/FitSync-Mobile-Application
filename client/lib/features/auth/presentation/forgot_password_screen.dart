import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import 'auth_controller.dart';

/// Requests a password-reset link for an email address.
///
/// The server answers every request the same way — a 202, whatever the
/// address — precisely so this screen can never be used to learn who has an
/// account. It must not undo that: the confirmation below is shown
/// unconditionally, on success and on failure alike (a network error
/// included). Anything else — a distinct error message, a different result
/// for an address that doesn't exist — would hand back exactly the
/// information the server refused to give.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String? _validationError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;

    if (_email.text.trim().isEmpty) {
      setState(() => _validationError = 'Enter your email.');
      return;
    }
    if (!_email.text.contains('@')) {
      setState(() => _validationError = 'That does not look like an email.');
      return;
    }

    setState(() {
      _busy = true;
      _validationError = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_email.text.trim());
    } catch (_) {
      // Deliberately swallowed — see the class doc. Whatever went wrong, an
      // unrecognised address, a network failure, anything at all, the user
      // sees the same confirmation either way.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _sent = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _sent
                ? [
                    Text(
                      "If that address has an account, we've sent a link.",
                      key: const Key('confirmation'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: t.text2, height: 1.5),
                    ),
                  ]
                : [
                    Text(
                      'Reset your\npassword.',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Enter your email and we'll send a link to reset your "
                      'password.',
                      style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    FsField(
                      fieldKey: const Key('email'),
                      controller: _email,
                      hint: 'you@email.com',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    if (_validationError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _validationError!,
                        key: const Key('error'),
                        style: TextStyle(fontSize: 12.5, color: t.red),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FsButton(
                      key: const Key('submit'),
                      label: 'Send reset link',
                      busy: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
