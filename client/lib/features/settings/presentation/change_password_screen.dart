import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/editable_under.dart';
import '../../auth/presentation/password_reveal_toggle.dart';
import '../../onboarding/presentation/edit_scaffold.dart';

/// The shortest password the server accepts, as on register and reset.
const _minPasswordLength = 8;

/// `WRONG_PASSWORD`, said under the current-password field it is about.
const _wrongPasswordMessage = "That password isn't right.";

/// Settings > Account > Change password: the current password, a new one,
/// and the new one again.
///
/// The server signs every other device out and hands this one a fresh
/// token, which the repository stores; the SnackBar says so, so a user whose
/// tablet asks them to sign in again knows why.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

/// The three fields, in the order they are drawn and checked.
enum _Field { current, next, confirm }

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _controllers = {
    for (final field in _Field.values) field: TextEditingController(),
  };

  /// One per field, around its [FsLabeledField], so a failed check can put
  /// the cursor in the field it is about.
  final _fieldKeys = {for (final field in _Field.values) field: GlobalKey()};

  /// Each field starts hidden; its eye reveals only that one.
  final _obscured = {for (final field in _Field.values) field: true};

  bool _busy = false;

  /// A message about one field, drawn under it.
  ({_Field field, String message})? _fieldError;

  /// A failure of the request as a whole, above the button.
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _text(_Field field) => _controllers[field]!.text;

  /// Anything typed is worth asking about before back throws it away.
  bool get _dirty => _controllers.values.any((c) => c.text.isNotEmpty);

  /// The first problem, top down, or null when the form can be sent. The
  /// length and the match are checked here rather than after a round trip.
  ({_Field field, String message})? _validate() {
    if (_text(_Field.current).isEmpty) {
      return (field: _Field.current, message: 'Enter your current password.');
    }
    if (_text(_Field.next).length < _minPasswordLength) {
      return (
        field: _Field.next,
        message: 'Use at least $_minPasswordLength characters.',
      );
    }
    if (_text(_Field.confirm) != _text(_Field.next)) {
      return (field: _Field.confirm, message: "The passwords don't match.");
    }
    return null;
  }

  /// Takes the cursor to [field], or reads [message] when it is already
  /// there, as the sign-in form does: see [focusOrAnnounce].
  void _focus(_Field field, String message) =>
      focusOrAnnounce(context, _fieldKeys[field]!, message);

  void _edited(_Field field) => setState(() {
    // The message described the old text; it would wrongly blame the new.
    if (_fieldError?.field == field) _fieldError = null;
  });

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _validate();
    if (problem != null) {
      setState(() {
        _fieldError = problem;
        _error = null;
      });
      _focus(problem.field, problem.message);
      return;
    }

    setState(() {
      _busy = true;
      _fieldError = null;
      _error = null;
    });
    // Read before the await: this screen pops itself on success, and the
    // SnackBar belongs on what is left.
    final repo = ref.read(authRepositoryProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await repo.changePassword(
        currentPassword: _text(_Field.current),
        newPassword: _text(_Field.next),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error.code == 'WRONG_PASSWORD') {
          _fieldError = (field: _Field.current, message: _wrongPasswordMessage);
        } else {
          _error = userMessage(error);
        }
      });
      if (error.code == 'WRONG_PASSWORD') {
        _focus(_Field.current, _wrongPasswordMessage);
      }
      return;
    }

    // The new token is stored whether or not the screen is still up. Back
    // stays open while busy, so the user may have left already: the change
    // landed all the same, and the SnackBar on what is left says so.
    if (mounted) {
      // Offer the password manager the password now in effect, before the
      // group closes and cancels: see the AutofillGroup in [build].
      TextInput.finishAutofillContext();
      navigator.pop();
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Password changed. Other devices were signed out.'),
      ),
    );
  }

  Widget _passwordField(
    _Field field, {
    required String label,
    required String hint,
    required String what,
    required String autofill,
    String? helper,
    TextInputAction action = TextInputAction.next,
  }) {
    final key = switch (field) {
      _Field.current => 'password.current',
      _Field.next => 'password.new',
      _Field.confirm => 'password.confirm',
    };
    final obscured = _obscured[field]!;
    return FsLabeledField(
      key: _fieldKeys[field],
      label: label,
      helper: helper,
      error: _fieldError?.field == field ? _fieldError!.message : null,
      field: FsField(
        fieldKey: Key(key),
        controller: _controllers[field]!,
        hint: hint,
        icon: Icons.lock_outline,
        obscure: obscured,
        textInputAction: action,
        autofillHints: [autofill],
        onChanged: (_) => _edited(field),
        onSubmitted: action == TextInputAction.done ? (_) => _submit() : null,
        trailing: PasswordRevealToggle(
          key: Key('$key.reveal'),
          obscured: obscured,
          what: what,
          onPressed: () => setState(() => _obscured[field] = !obscured),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditScaffold(
      title: 'Change password',
      saveLabel: 'Change password',
      // Cut at 2x text on a 320 dp phone otherwise ("Change passw…").
      wrapSaveLabel: true,
      busy: _busy,
      dirty: _dirty,
      error: _error,
      onSave: _submit,
      // One group, so a password manager offers to update the saved one.
      // Closing it cancels: a new password that never took effect must not
      // be offered for saving, possibly over the right one. A change that
      // lands commits it in [_submit] first.
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _passwordField(
              _Field.current,
              label: 'Current password',
              hint: 'Your password',
              what: 'current password',
              autofill: AutofillHints.password,
            ),
            const SizedBox(height: 14),
            _passwordField(
              _Field.next,
              label: 'New password',
              hint: 'Create a password',
              what: 'new password',
              autofill: AutofillHints.newPassword,
              helper: 'At least $_minPasswordLength characters',
            ),
            const SizedBox(height: 14),
            _passwordField(
              _Field.confirm,
              label: 'Confirm new password',
              hint: 'The new password again',
              // Not 'new password' again: TalkBack would read two different
              // toggles alike, "Show new password".
              what: 'confirmed password',
              autofill: AutofillHints.newPassword,
              action: TextInputAction.done,
            ),
          ],
        ),
      ),
    );
  }
}
