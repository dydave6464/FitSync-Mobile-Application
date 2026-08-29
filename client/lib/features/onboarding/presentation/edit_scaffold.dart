import 'package:flutter/material.dart';

/// Editor chrome around the same step widgets the wizard uses.
///
/// Deliberately carries no progress indicator and no Skip: editing one answer
/// from Settings is not a position in a sequence, and there is nothing to skip
/// past. That difference is the only reason this is a second wrapper rather
/// than a flag on [OnboardingScaffold].
class EditScaffold extends StatelessWidget {
  const EditScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onSave,
    this.busy = false,
  });

  final String title;
  final Widget child;
  final VoidCallback onSave;
  final bool busy;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
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
              key: const Key('save'),
              onPressed: busy ? null : onSave,
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ),
      );
}
