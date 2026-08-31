import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../domain/plan_energy.dart';

/// The today's-plan card.
///
/// The cover is a gradient band rather than a photograph: nothing to ship as
/// an asset, and no second unlicensed image in a repository that already
/// carries an unresolved media-licensing risk for the exercise animations.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.weightKg,
    required this.onStart,
  });

  final WorkoutPlan plan;
  final double? weightKg;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final kcal = estimateSessionKcal(plan: plan, weightKg: weightKg);

    final meta = [
      '${plan.exercises.length} exercises',
      '~${plan.sessionLengthMin} min',
      // Omitted rather than guessed when body weight is unknown.
      if (kcal != null) '~$kcal kcal',
    ].join(' · ');

    return FsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 116,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(FsRadius.card),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.accent.withValues(alpha: 0.16),
                  t.accent.withValues(alpha: 0.03),
                ],
              ),
            ),
            child: FsEyebrow(describeSplit(plan.splitStyle)),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FsEyebrow("Today's plan"),
                const SizedBox(height: 8),
                Text(plan.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(meta, style: TextStyle(fontSize: 12.5, color: t.text2)),
                const SizedBox(height: 14),
                FsButton(
                  label: 'Start workout',
                  small: true,
                  icon: const Icon(Icons.play_arrow),
                  onPressed: onStart,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
