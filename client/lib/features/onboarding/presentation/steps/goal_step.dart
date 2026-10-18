import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../profile/domain/profile.dart';

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

/// The server's `main_goal` / `goals` wire values, in card order. The single
/// source for that order: onboarding and Settings seed their working state
/// from this instead of keeping a second list that could drift from the
/// cards actually rendered below.
final goalValues = [for (final g in _goals) g.value];

/// The goal step's answer: every ticked goal, in card order, and the main
/// focus -- the one goal that sets the plan's sets and reps.
class GoalAnswers {
  const GoalAnswers({this.goals = const [], this.mainGoal});

  final List<String> goals;
  final String? mainGoal;

  /// Seeds a working value from the saved profile: every ticked goal, in
  /// card order, and a focus guaranteed to be among them (or null when there
  /// are none) -- even when the profile itself disagrees, e.g. a main focus
  /// left behind after the goal it named was removed elsewhere. Onboarding
  /// and Settings both call this instead of repeating the same comprehension.
  factory GoalAnswers.fromProfile(Profile profile) {
    final goals = [
      for (final g in goalValues)
        if (profile.goals.contains(g)) g,
    ];
    final mainGoal = goals.contains(profile.mainGoal)
        ? profile.mainGoal
        : (goals.isEmpty ? null : goals.first);
    return GoalAnswers(goals: goals, mainGoal: mainGoal);
  }
}

/// Step 1: what the user is training for.
///
/// A pure content widget — it takes the current value, reports changes, and
/// has no idea whether it is inside the onboarding wizard or the Settings
/// editor. Do not give it a provider or a save button.
///
/// Multi-select: any number of goals can be ticked. The first one ticked
/// becomes the main focus -- the one goal that sets the plan's sets and reps
/// -- shown as a row of chips once two or more goals are ticked, and
/// switchable there. Unticking the focus hands it to the first goal still
/// ticked, in card order; unticking every goal clears it.
class GoalStep extends StatelessWidget {
  const GoalStep({super.key, required this.value, required this.onChanged});

  final GoalAnswers value;
  final ValueChanged<GoalAnswers> onChanged;

  void _toggle(String goal) {
    final ticked = value.goals.contains(goal);
    final next = [
      for (final g in _goals)
        if (g.value == goal ? !ticked : value.goals.contains(g.value)) g.value,
    ];
    // A focus that is not among the goals ticked right now counts as none --
    // whether that is because nothing has been ticked yet, or because the
    // value handed in (e.g. seeded from a profile) is stale. Carrying a
    // stale focus forward is what used to reach the server as mainGoal for a
    // goal that was not ticked, and crash the save.
    final currentFocus = value.goals.contains(value.mainGoal)
        ? value.mainGoal
        : null;
    final hasNoFocus = currentFocus == null || (ticked && currentFocus == goal);
    final focus = hasNoFocus
        ? (next.isEmpty ? null : next.first)
        : currentFocus;
    onChanged(GoalAnswers(goals: next, mainGoal: focus));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('What are your goals?', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Pick all that apply. You can change them later.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 20),
        for (final goal in _goals) ...[
          FsCard(
            key: Key('goal.${goal.value}'),
            small: true,
            accent: value.goals.contains(goal.value),
            selected: value.goals.contains(goal.value),
            onTap: () => _toggle(goal.value),
            child: Row(
              children: [
                FsIconTile(
                  icon: goal.icon,
                  selected: value.goals.contains(goal.value),
                ),
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
                FsRadioDot(selected: value.goals.contains(goal.value)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (value.goals.length >= 2) ...[
          const SizedBox(height: 14),
          const FsEyebrow('Main focus'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final goal in _goals)
                if (value.goals.contains(goal.value))
                  FsChip(
                    key: Key('focus.${goal.value}'),
                    label: goal.label,
                    selected: value.mainGoal == goal.value,
                    small: true,
                    onTap: () => onChanged(
                      GoalAnswers(goals: value.goals, mainGoal: goal.value),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your main focus sets your sets and reps.',
            style: TextStyle(fontSize: 11.5, color: t.text3),
          ),
        ],
      ],
    );
  }
}
