import 'package:flutter/material.dart';

/// Wizard chrome around a step: where you are, how to go on, how to go back.
///
/// It knows nothing about what the step contains, and the step knows nothing
/// about this. That separation is the whole point — the same step widget is
/// wrapped in [EditScaffold] when it is reached from Settings instead.
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: onBack == null
              ? null
              : IconButton(
                  key: const Key('back'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: busy ? null : onBack,
                ),
          automaticallyImplyLeading: false,
          title: Text('Step $step of $total'),
          actions: [
            if (onSkip != null)
              TextButton(
                key: const Key('skip'),
                onPressed: busy ? null : onSkip,
                child: const Text('Skip'),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: step / total),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('continue'),
              onPressed: busy ? null : onContinue,
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(continueLabel),
            ),
          ),
        ),
      );
}
