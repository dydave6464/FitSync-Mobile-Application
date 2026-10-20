import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';

/// Step 6: offers reminders before the plan is built.
///
/// Two switches, owned by OnboardingFlow, which also owns the buttons: the
/// scaffold's Continue ("Turn on reminders") saves them after the permission
/// prompt, and "Not now" saves nothing. Both start on -- the check-in
/// reminder is what brings the morning check-ins in, and the injury-risk
/// estimate is only as good as those.
class RemindersStep extends StatelessWidget {
  const RemindersStep({
    super.key,
    required this.habits,
    required this.checkin,
    required this.onHabitsChanged,
    required this.onCheckinChanged,
  });

  final bool habits;
  final bool checkin;
  final ValueChanged<bool> onHabitsChanged;
  final ValueChanged<bool> onCheckinChanged;

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
          'Pick what to be reminded about. You can change these any time in '
          'Settings.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 14),
        FsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReminderRow(
                key: const Key('onboarding.remind.habits'),
                switchKey: const Key('onboarding.remind.habits.switch'),
                label: 'Habits',
                detail: '15 minutes before each timed habit',
                value: habits,
                onChanged: onHabitsChanged,
              ),
              Divider(color: t.line2, height: 1),
              _ReminderRow(
                key: const Key('onboarding.remind.checkin'),
                switchKey: const Key('onboarding.remind.checkin.switch'),
                label: 'Morning check-in',
                detail: '7:00 AM · four quick questions',
                value: checkin,
                onChanged: onCheckinChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Both buttons lead straight into building the plan, so say so
        // before either is pressed rather than let the next screen surprise.
        Text(
          "Next, we'll build your plan.",
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
      ],
    );
  }
}

/// One reminder: what it is, when it fires, and its switch. The whole row is
/// the tap target, and a screen reader hears it as one toggle -- "Morning
/// check-in, 7:00 AM · four quick questions" -- rather than a bare switch.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    super.key,
    required this.switchKey,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Semantics(
      container: true,
      toggled: value,
      label: '$label, $detail',
      onTap: () => onChanged(!value),
      excludeSemantics: true,
      // Transparent Material so the ripple draws on the card, not under it.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: TextStyle(
                            fontSize: 12,
                            color: t.text2,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(key: switchKey, value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
