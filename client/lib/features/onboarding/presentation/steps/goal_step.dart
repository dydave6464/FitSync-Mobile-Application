import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';

/// The four goals, paired with the exact `main_goal` ENUM values the server
/// accepts. Labels and order follow the prototype; the value is a wire
/// contract and may not change with them.
const _goals = <({String value, String label, String blurb, IconData icon})>[
  (
    value: 'build_muscle',
    label: 'Build muscle',
    blurb: 'Hypertrophy & strength',
    icon: Icons.fitness_center,
  ),
  (
    value: 'lose_weight',
    label: 'Lose fat',
    blurb: 'Lean out, stay strong',
    icon: Icons.local_fire_department_outlined,
  ),
  (
    value: 'improve_endurance',
    label: 'Improve endurance',
    blurb: 'Conditioning & stamina',
    icon: Icons.monitor_heart_outlined,
  ),
  (
    value: 'general_fitness',
    label: 'General health',
    blurb: 'Move better, feel good',
    icon: Icons.favorite_outline,
  ),
];

/// Step 1: what the user is training for.
///
/// A pure content widget — it takes the current value, reports changes, and
/// has no idea whether it is inside the onboarding wizard or the Settings
/// editor. Do not give it a provider or a save button.
class GoalStep extends StatelessWidget {
  const GoalStep({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("What's your\nmain goal?", style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'We tailor your plan around this. You can change it later.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 20),
        for (final goal in _goals) ...[
          FsCard(
            key: Key('goal.${goal.value}'),
            small: true,
            accent: value == goal.value,
            onTap: () => onChanged(goal.value),
            child: Row(
              children: [
                FsIconTile(icon: goal.icon, selected: value == goal.value),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        goal.blurb,
                        style: TextStyle(fontSize: 11, color: t.text3),
                      ),
                    ],
                  ),
                ),
                FsRadioDot(selected: value == goal.value),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
