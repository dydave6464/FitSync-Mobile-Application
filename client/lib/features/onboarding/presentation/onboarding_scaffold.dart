import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';

/// Wizard chrome around a step: where you are, how to go on, how to go back.
///
/// It knows nothing about what the step contains, and the step knows nothing
/// about this. That separation is the whole point — the same step widget is
/// wrapped in [EditScaffold] when it is reached from Settings instead.
///
/// Layout follows the prototype's `OnbHead`: a back control, a mono step
/// counter and Skip on one row, then one progress bar per step.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.total,
    required this.child,
    required this.onContinue,
    this.onSkip,
    this.onBack,
    this.continueLabel = 'Continue',
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
    this.error,
    this.hint,
    this.onSignOut,
  });

  final int step;
  final int total;
  final Widget child;

  /// Null disables Continue: a step whose answer is not yet valid.
  final VoidCallback? onContinue;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;
  final String continueLabel;

  /// When set, rendered as a secondary button directly under Continue,
  /// instead of the header's narrow Skip slot. The last step uses this for
  /// "Not now": declining reminders is a real second choice, not a question
  /// to skip past, and its label did not fit that cramped corner slot
  /// without wrapping.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;

  /// What went wrong with the last Continue, in plain words. Shown directly
  /// above Continue rather than under the step's content, where on a long
  /// step it landed below the fold and the user saw nothing happen.
  final String? error;

  /// Why Continue is greyed out, when the step can say. Shown directly above
  /// it for the same reason as [error]: at the end of a long step's content
  /// it could be scrolled out of sight of the button it explains.
  final String? hint;

  /// When set, a small "Sign out" under the buttons: the way out for someone
  /// who signed in with the wrong account and would otherwise have to finish
  /// onboarding for it first.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The header's controls take 48dp taps around a 38dp drawing. The
            // 5dp of slack on each side is taken out of the padding around
            // them, so what is drawn sits exactly where it did.
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 3, 15, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: _HeaderButton.target,
                        child: onBack == null
                            ? null
                            : _HeaderButton(
                                key: const Key('back'),
                                icon: Icons.chevron_left,
                                label: 'Back',
                                onTap: busy ? null : onBack,
                              ),
                      ),
                      Expanded(
                        child: Center(child: FsEyebrow('Step $step / $total')),
                      ),
                      // At least as wide as the back slot, so the counter
                      // stays centred; wider only when large text needs it.
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: _HeaderButton.target,
                        ),
                        child: onSkip == null
                            ? null
                            : InkWell(
                                key: const Key('skip'),
                                onTap: busy ? null : onSkip,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: _HeaderButton.target,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 5),
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      widthFactor: 1,
                                      heightFactor: 1,
                                      child: Text(
                                        'Skip',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: t.text3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  FsStepBars(step: step, total: total),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                child: child,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) ...[
                    _ErrorLine(error!),
                    const SizedBox(height: 10),
                  ],
                  if (hint != null) ...[
                    ContinueHint(hint!),
                    const SizedBox(height: 10),
                  ],
                  FsButton(
                    key: const Key('continue'),
                    label: continueLabel,
                    busy: busy,
                    onPressed: busy ? null : onContinue,
                  ),
                  if (secondaryLabel != null) ...[
                    const SizedBox(height: 10),
                    FsButton(
                      key: const Key('secondary'),
                      label: secondaryLabel!,
                      kind: FsButtonKind.secondary,
                      onPressed: busy ? null : onSecondary,
                    ),
                  ],
                  if (onSignOut != null) ...[
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        key: const Key('signOut'),
                        onPressed: busy ? null : onSignOut,
                        style: TextButton.styleFrom(
                          foregroundColor: t.text2,
                          minimumSize: const Size(48, 48),
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Sign out'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last Continue's failure. The icon carries the red so the sentence
/// itself can stay in body text, which reads at full contrast in both themes.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Row(
      key: const Key('error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline, size: 16, color: t.red),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 13, height: 1.4, color: t.text),
          ),
        ),
      ],
    );
  }
}

/// Why the button under it cannot be pressed yet. Shared with [EditScaffold],
/// whose Save is greyed out for the same reasons.
///
/// Body grey rather than the faint tertiary: it is the one sentence that
/// explains a button which otherwise reads as broken.
class ContinueHint extends StatelessWidget {
  const ContinueHint(this.message, {super.key = const Key('hint')});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12.5, color: context.fs.text2, height: 1.5),
    );
  }
}

/// `.icon-btn` — a bordered square, drawn at 38dp inside a 48dp tap target.
///
/// A tap on the square reaches its own ink; one in the slack around it does
/// the same thing, so the prototype's compact header keeps its look without
/// a target a thumb can miss.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  static const target = 48.0;

  final IconData icon;

  /// What a screen reader says for it; the glyph alone says nothing.
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: target,
          child: Center(
            child: Material(
              color: t.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FsRadius.sm),
                side: BorderSide(color: t.line),
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(FsRadius.sm),
                child: SizedBox(
                  height: 38,
                  width: 38,
                  child: Icon(icon, size: 19, color: t.text2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
