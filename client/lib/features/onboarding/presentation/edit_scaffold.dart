import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';

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
  });

  final String title;
  final Widget child;
  final VoidCallback onSave;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Scaffold(
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
              child: FsButton(
                key: const Key('save'),
                label: 'Save',
                busy: busy,
                onPressed: busy ? null : onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
