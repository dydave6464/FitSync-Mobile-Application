import 'package:flutter/material.dart';

/// The four goals, paired with the exact `main_goal` ENUM values the server
/// accepts. The label is display text and may be reworded freely; the value
/// is a wire contract and may not.
const _goals = <({String value, String label, String blurb, IconData icon})>[
  (
    value: 'lose_weight',
    label: 'Lose weight',
    blurb: 'Burn fat while keeping the muscle you have',
    icon: Icons.trending_down,
  ),
  (
    value: 'build_muscle',
    label: 'Build muscle',
    blurb: 'Add size and strength',
    icon: Icons.fitness_center,
  ),
  (
    value: 'improve_endurance',
    label: 'Improve endurance',
    blurb: 'Last longer and recover faster',
    icon: Icons.directions_run,
  ),
  (
    value: 'general_fitness',
    label: 'Stay generally fit',
    blurb: 'Feel better day to day',
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "What's your main goal?",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'This shapes how your plan is built. You can change it later.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final goal in _goals)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: Key('goal.${goal.value}'),
                selected: value == goal.value,
                leading: Icon(goal.icon),
                title: Text(goal.label),
                subtitle: Text(goal.blurb),
                trailing:
                    value == goal.value ? const Icon(Icons.check_circle) : null,
                onTap: () => onChanged(goal.value),
              ),
            ),
        ],
      );
}
