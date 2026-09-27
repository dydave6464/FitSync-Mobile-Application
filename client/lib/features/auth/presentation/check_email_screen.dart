import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import 'auth_controller.dart';
import 'code_entry.dart';

/// Shown once an account exists but cannot sign in yet: right after
/// registration, and again when a login attempt comes back
/// `EMAIL_NOT_VERIFIED`. The server emails a 6-digit code; typing it here
/// verifies the address, and the app then signs in with the email and
/// password it was handed -- the same ones just typed into the form that led
/// here -- so there is no second sign-in step.
class CheckEmailScreen extends ConsumerStatefulWidget {
  const CheckEmailScreen({
    super.key,
    required this.email,
    required this.password,
  });

  final String email;

  /// Carried along rather than re-asked for: `/verify-email/request` takes a
  /// password because there is no JWT yet, and signing in after a correct
  /// code needs it too.
  final String password;

  @override
  ConsumerState<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends ConsumerState<CheckEmailScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  /// Set once the server accepts the code. From then on the button only
  /// retries the sign-in: the code is spent, and sending it again would come
  /// back CODE_INVALID for an address that is in fact verified.
  bool _verified = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
  }

  void _onCodeChanged() => setState(() {});

  @override
  void dispose() {
    _code.removeListener(_onCodeChanged);
    _code.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && (_verified || _code.text.length == 6);

  Future<void> _verify() async {
    if (!_canSubmit) return;
    // Read before any await: the screen can be gone by the time one resolves.
    final repo = ref.read(authRepositoryProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      if (!_verified) {
        await repo.verifyEmail(email: widget.email, code: _code.text);
        _verified = true;
      }
      final user = await repo.login(widget.email, widget.password);
      navigator.popUntil((route) => route.isFirst);
      controller.onAuthenticated(user);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _verified
            ? 'Your email is verified. Tap to sign in.'
            : (error.code == 'CODE_INVALID' ? wrongCodeMessage : error.message);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    final repo = ref.read(authRepositoryProvider);
    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      await repo.resendVerification(
        email: widget.email,
        password: widget.password,
      );
      if (!mounted) return;
      setState(() => _status = newCodeMessage);
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
                const Center(
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
                  'We sent a 6-digit code to ${widget.email}. Enter it below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
                ),
                const SizedBox(height: 22),
                if (!_verified) CodeField(controller: _code),
                if (_status != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _status!,
                    key: const Key('status'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: t.text2),
                  ),
                ],
                const SizedBox(height: 18),
                FsButton(
                  key: const Key('verify'),
                  label: _verified ? 'Sign in' : 'Verify',
                  busy: _busy,
                  onPressed: _canSubmit ? _verify : null,
                ),
                if (!_verified) ...[
                  const SizedBox(height: 10),
                  FsButton(
                    key: const Key('resend'),
                    label: 'Send a new code',
                    kind: FsButtonKind.secondary,
                    onPressed: _busy ? null : _resend,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
