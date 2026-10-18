import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../../profile/domain/profile.dart' show fitnessLevelLabel;

/// Home's welcome for a plan onboarding has just built.
///
/// Without it the new plan was buried under the check-in card, and nothing on
/// the first screen said the wait had produced anything (UX review row 6). It
/// says so once, at the top, with the plan's shape and the one way in to it;
/// whether it shows at all is `planReadyProvider`'s to decide, not this
/// card's.
class PlanReadyCard extends StatelessWidget {
  const PlanReadyCard({
    super.key,
    required this.plan,
    required this.fitnessLevel,
    required this.onSeePlan,
    required this.onDismiss,
  });

  final WorkoutPlan plan;

  /// The profile's `fitness_level`. Null when the step was skipped, and then
  /// left off rather than guessed: the generator plans a skipped level as a
  /// beginner, but the user never said so.
  final String? fitnessLevel;

  final VoidCallback onSeePlan;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final days = plan.daysPerWeek;
    final facts = [
      '$days ${days == 1 ? 'day' : 'days'} a week',
      '~${plan.sessionLengthMin} min',
      if (fitnessLevel != null) fitnessLevelLabel(fitnessLevel!),
    ];

    return FsCard(
      key: const Key('home.planReady'),
      accent: true,
      // Tight top and right so the close button's 48 dp box sits in the
      // corner, the way the design draws the ✕; the rest of the card makes
      // up the difference below.
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Decoration beside words that already say it.
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: t.accentText,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'YOUR PLAN IS READY',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              // The eyebrow's type in the words' green: the
                              // brand green is under 3:1 as text on its own
                              // tint.
                              style: fsEyebrow(t).copyWith(color: t.accentText),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(plan.name, style: theme.textTheme.titleLarge),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const Key('home.planReady.dismiss'),
                icon: const Icon(Icons.close, size: 20),
                color: t.text2,
                // The words a bare ✕ cannot carry, for a screen reader.
                tooltip: 'Dismiss',
                onPressed: onDismiss,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final fact in facts) _Fact(fact, t: t)],
                ),
                const SizedBox(height: 14),
                FsButton(
                  label: 'See plan',
                  small: true,
                  icon: const Icon(Icons.event_note),
                  onPressed: onSeePlan,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One fact about the plan, drawn as the plan card's focus chips are.
class _Fact extends StatelessWidget {
  const _Fact(this.text, {required this.t});

  final String text;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(FsRadius.pill),
        border: Border.all(color: t.accentLine),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: t.text,
        ),
      ),
    );
  }
}
