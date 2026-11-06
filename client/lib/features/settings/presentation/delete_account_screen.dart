import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../auth/data/google_sign_in_gateway.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/editable_under.dart';
import '../../auth/presentation/google_g_mark.dart';
import '../../auth/presentation/password_reveal_toggle.dart';

/// What the account holds, said plainly before anything is deleted. Every
/// table of user data goes with the account (the server deletes the user
/// row, and the rest cascades).
const _whatIsDeleted = [
  'Your profile, health answers and injuries',
  'Your plans, workouts and progress',
  'Your meals, weigh-ins and step counts',
  'Your routine, reminders, streaks and goals',
  'Your FitSync Pro membership and payment history',
];

const _wrongPasswordMessage = "That password isn't right.";
const _googleMismatchMessage =
    "That Google account isn't the one this account uses.";
const _googleFailedMessage = "Couldn't confirm with Google. Try again.";

/// Settings > Account > Delete account.
///
/// Immediate once confirmed: the owner proves it is them -- the password,
/// or for an account without one a fresh Google sign-in -- then a last
/// dialog, then the server deletes everything. Afterwards the same local
/// clean-up as Sign out runs and the sign-in screen says why the user is
/// there.
///
/// Unlike the app's other typed forms, back is not behind an
/// [FsDiscardGuard]: leaving is the safe way out of a deletion, and the only
/// thing typed is the password, which costs nothing to type again. Asking
/// "Discard your changes?" with a red Discard would stand between the user
/// and changing their mind.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key, required this.hasPassword});

  /// Whether to confirm with a password; without one, with Google.
  final bool hasPassword;

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

/// Which request is on its way, so only its button spins.
enum _Pending { none, google, delete }

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _passwordKey = GlobalKey();
  bool _obscured = true;

  _Pending _pending = _Pending.none;
  bool get _busy => _pending != _Pending.none;

  /// A fresh Google ID token, once the user has confirmed with Google.
  String? _idToken;

  /// About the password field, drawn under it.
  String? _passwordError;

  /// About the request as a whole, above the Delete button.
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  /// Takes the cursor to the password field, or reads [message] when it is
  /// already there: see [focusOrAnnounce].
  void _focusPassword(String message) =>
      focusOrAnnounce(context, _passwordKey, message);

  Future<void> _confirmWithGoogle() async {
    if (_busy) return;
    setState(() {
      _pending = _Pending.google;
      _error = null;
    });
    try {
      final result = await ref.read(googleSignInGatewayProvider).signIn();
      if (!mounted) return;
      setState(() {
        switch (result) {
          case GoogleSignInToken(:final idToken):
            _idToken = idToken;
          // Closing the picker is a decision: nothing to say.
          case GoogleSignInCancelled():
            break;
          case GoogleSignInFailed(:final cause):
            if (kDebugMode) debugPrint('Google confirm failed: $cause');
            _error = _googleFailedMessage;
        }
      });
    } finally {
      if (mounted) setState(() => _pending = _Pending.none);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (widget.hasPassword && _password.text.isEmpty) {
      setState(() {
        _passwordError = 'Enter your password.';
        _error = null;
      });
      _focusPassword('Enter your password.');
      return;
    }
    if (!widget.hasPassword && _idToken == null) {
      setState(() => _error = 'Confirm with Google first.');
      return;
    }
    // The last word: Keep account, or Delete in red.
    final confirmed = await confirmDestructive(
      context,
      keyPrefix: 'deleteAccount',
      title: 'Delete your account?',
      message: 'Your account and everything in it are deleted for good.',
      action: 'Delete',
      cancel: 'Keep account',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _pending = _Pending.delete;
      _passwordError = null;
      _error = null;
    });
    // Read before the await: once the account is gone the clean-up must run
    // even if this screen was closed meanwhile, or the phone keeps a token
    // for an account that no longer exists.
    final repo = ref.read(authRepositoryProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final navigator = Navigator.of(context);

    try {
      await repo.deleteAccount(
        password: widget.hasPassword ? _password.text : null,
        idToken: widget.hasPassword ? null : _idToken,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _pending = _Pending.none;
        switch (error.code) {
          case 'WRONG_PASSWORD':
            _passwordError = _wrongPasswordMessage;
          case 'GOOGLE_ACCOUNT_MISMATCH':
            // That confirmation was for another account: ask for a new one.
            _idToken = null;
            _error = _googleMismatchMessage;
          default:
            _error = userMessage(error);
        }
      });
      if (error.code == 'WRONG_PASSWORD') _focusPassword(_wrongPasswordMessage);
      return;
    }

    // Back to the shell first, which then shows sign-in: a pushed route
    // left on top would cover it.
    navigator.popUntil((route) => route.isFirst);
    await controller.onAccountDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final body = TextStyle(fontSize: 13.5, height: 1.45, color: t.text);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Delete account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Deleting your account removes everything in it:',
                style: body,
              ),
              const SizedBox(height: 10),
              for (final item in _whatIsDeleted) _Bullet(item),
              const SizedBox(height: 10),
              Text(
                "This can't be undone.",
                style: body.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              if (widget.hasPassword)
                _passwordField(t)
              else
                ..._googleConfirm(t),
              const SizedBox(height: 22),
              if (_error != null) ...[
                FsErrorLine(_error!, key: const Key('deleteAccount.error')),
                const SizedBox(height: 10),
              ],
              FsButton(
                key: const Key('deleteAccount.submit'),
                label: 'Delete my account',
                kind: FsButtonKind.ghost,
                danger: true,
                // Read whole at 2x on a 320 dp phone, not "Delete my acc…".
                wrapLabel: true,
                busy: _pending == _Pending.delete,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Closing cancels rather than commits: a password that confirmed a
  // deletion belongs to an account that no longer exists, and one typed and
  // left behind was never checked.
  Widget _passwordField(FsTokens t) => AutofillGroup(
    onDisposeAction: AutofillContextAction.cancel,
    child: FsLabeledField(
      key: _passwordKey,
      label: 'Password',
      helper: "Enter your password to confirm it's you.",
      error: _passwordError,
      field: FsField(
        fieldKey: const Key('deleteAccount.password'),
        controller: _password,
        hint: 'Your password',
        icon: Icons.lock_outline,
        obscure: _obscured,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        onChanged: (_) {
          if (_passwordError != null) setState(() => _passwordError = null);
        },
        onSubmitted: (_) => _submit(),
        trailing: PasswordRevealToggle(
          key: const Key('deleteAccount.password.reveal'),
          obscured: _obscured,
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    ),
  );

  List<Widget> _googleConfirm(FsTokens t) => [
    Text(
      "You sign in with Google. Confirm it's you with the same Google "
      'account.',
      style: TextStyle(fontSize: 12.5, height: 1.45, color: t.text2),
    ),
    const SizedBox(height: 12),
    FsButton(
      key: const Key('deleteAccount.google'),
      label: 'Confirm with Google',
      kind: FsButtonKind.secondary,
      small: true,
      wrapLabel: true,
      icon: const GoogleGMark(),
      busy: _pending == _Pending.google,
      onPressed: _busy ? null : _confirmWithGoogle,
    ),
    if (_idToken != null) ...[
      const SizedBox(height: 8),
      Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: t.accentText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirmed with Google.',
                style: TextStyle(fontSize: 13, color: t.text),
              ),
            ),
          ],
        ),
      ),
    ],
  ];
}

/// One line of the list of what is deleted.
class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The dot is decoration; the line reads the same without it.
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 7, 10, 0),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: t.text3,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text2),
            ),
          ),
        ],
      ),
    );
  }
}
