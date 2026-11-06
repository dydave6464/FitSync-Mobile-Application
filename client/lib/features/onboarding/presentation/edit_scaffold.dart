import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import 'onboarding_scaffold.dart' show ContinueHint;

/// Editor chrome around the same step widgets the wizard uses.
///
/// Deliberately carries no progress bars and no Skip: editing one answer from
/// Settings is not a position in a sequence, and there is nothing to skip
/// past. That difference is the only reason this is a second wrapper rather
/// than a flag on [OnboardingScaffold].
class EditScaffold extends StatelessWidget {
  const EditScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onSave,
    this.busy = false,
    this.hint,
    this.dirty = false,
    this.error,
    this.saveLabel = 'Save',
  });

  final String title;

  /// The button's words, for an editor whose action is more than a save
  /// ("Change password").
  final String saveLabel;
  final Widget child;

  /// Null disables Save: the answer on screen is not yet valid.
  final VoidCallback? onSave;
  final bool busy;

  /// Why Save is greyed out, shown above it, as the wizard does for
  /// Continue: above [error] when both are up, as there.
  final String? hint;

  /// Whether the answer on screen differs from the one the editor opened
  /// with. While it does, back asks before throwing the edits away -- many
  /// settings save as they are tapped, so a user reasonably expects back to
  /// keep them here too. Not while a save is in flight: that edit is already
  /// on its way.
  final bool dirty;

  /// Why the last Save failed, in plain words. Shown directly above Save,
  /// where it is in view whenever Save is: under a long editor's content it
  /// landed below the fold, and the user saw only the spinner stop.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsDiscardGuard(
      dirty: dirty && !busy,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: child,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hint != null) ...[
                      ContinueHint(hint!),
                      const SizedBox(height: 10),
                    ],
                    if (error != null) ...[
                      FsErrorLine(error!, key: const Key('error')),
                      const SizedBox(height: 10),
                    ],
                    FsButton(
                      key: const Key('save'),
                      label: saveLabel,
                      busy: busy,
                      onPressed: busy ? null : onSave,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
