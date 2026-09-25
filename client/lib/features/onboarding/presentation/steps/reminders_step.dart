import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// Step 5: offers reminders before the plan is built.
///
/// Stateless -- there is nothing to answer here. The scaffold's own Continue
/// and Skip buttons carry the two choices ("Turn on reminders" / "Not now"),
/// wired by OnboardingFlow to request permission (or not) before the same
/// completion path either way runs.
class RemindersStep extends StatelessWidget {
  const RemindersStep({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Stay on track', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          "Reminders for your habits before they're due. You can change "
          'them any time in Settings.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
      ],
    );
  }
}
