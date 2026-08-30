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
    this.busy = false,
  });

  final int step;
  final int total;
  final Widget child;
  final VoidCallback onContinue;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;
  final String continueLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 38,
                        child: onBack == null
                            ? null
                            : _IconButton(
                                key: const Key('back'),
                                icon: Icons.chevron_left,
                                onTap: busy ? null : onBack,
                              ),
                      ),
                      Expanded(
                        child: Center(child: FsEyebrow('Step $step / $total')),
                      ),
                      SizedBox(
                        width: 38,
                        child: onSkip == null
                            ? null
                            : InkWell(
                                key: const Key('skip'),
                                onTap: busy ? null : onSkip,
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
                    ],
                  ),
                  const SizedBox(height: 16),
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
              child: FsButton(
                key: const Key('continue'),
                label: continueLabel,
                busy: busy,
                onPressed: busy ? null : onContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.icon-btn` — a bordered square tap target.
class _IconButton extends StatelessWidget {
  const _IconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Material(
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
    );
  }
}
