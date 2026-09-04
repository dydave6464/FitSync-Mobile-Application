import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import 'auth_controller.dart';

/// Shown once an account exists but cannot sign in yet: right after
/// registration, and again when a login attempt comes back
/// `EMAIL_NOT_VERIFIED`. Both cases resolve the same way — open the link the
/// server emailed and come back — so they share this one screen instead of
/// two near-identical messages.
///
/// The verification link opens a server-rendered page, not the app, so there
/// is no deep link to wait for here — only a Resend action for the case the
/// original email never arrived.
class CheckEmailScreen extends ConsumerStatefulWidget {
  const CheckEmailScreen({
    super.key,
    required this.email,
    required this.password,
  });

  final String email;

  /// Carried along rather than re-asked for: `/verify-email/request` takes a
  /// password because there is no JWT yet to prove who is asking, and the
  /// user just typed this same password into the form that led here.
  final String password;

  @override
  ConsumerState<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends ConsumerState<CheckEmailScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _resend() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      await ref.read(authRepositoryProvider).resendVerification(
            email: widget.email,
            password: widget.password,
          );
      if (!mounted) return;
      setState(() => _status = 'Email sent.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _status = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: FsIconTile(
                    icon: Icons.mail_outline,
                    selected: true,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Check your email',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  "We've sent a verification link to ${widget.email}. Open "
                  'it, then come back and sign in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _status!,
                    key: const Key('status'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: t.text2),
                  ),
                ],
                const SizedBox(height: 24),
                FsButton(
                  key: const Key('resend'),
                  label: 'Resend email',
                  kind: FsButtonKind.secondary,
                  busy: _busy,
                  onPressed: _busy ? null : _resend,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
