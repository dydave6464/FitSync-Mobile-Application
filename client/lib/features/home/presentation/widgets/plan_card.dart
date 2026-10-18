import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/domain/muscle_regions.dart';
import '../../../plans/domain/plan_energy.dart';
import '../../../plans/domain/workout_plan.dart';

/// The today's-plan card.
///
/// The cover is a gradient band rather than a photograph: nothing to ship as
/// an asset, and no second unlicensed image in a repository that already
/// carries an unresolved media-licensing risk for the exercise animations.
/// It carries today's focus instead: which day of the rotation this is, and
/// the areas its exercises work.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.weightKg,
    required this.onStart,
    this.dayNo,
  });

  final WorkoutPlan plan;
  final double? weightKg;
  final VoidCallback onStart;

  /// Which rotation day this card is describing — the caller works it out
  /// with [WorkoutPlan.todayDayNo], since it depends on how many sessions
  /// are already complete this week. Null reads as day 1, which is what a
  /// plan from a server predating per-day plans is.
  final int? dayNo;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final kcal = estimateSessionKcal(plan: plan, weightKg: weightKg);

    // Today's day, not the whole rotation: this card is titled "Today's
    // plan" and its button starts one session, so counting a three-day
    // rotation's exercises promised a workout three times the one that
    // starts. exercisesForDay is the single home of that filtering.
    final today = plan.exercisesForDay(dayNo);
    final exerciseCount = today.length;
    final meta = <(FaIconData, String)>[
      (
        FontAwesomeIcons.dumbbell,
        '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}',
      ),
      (FontAwesomeIcons.solidClock, '~${plan.sessionLengthMin} min'),
      // Omitted rather than guessed when body weight is unknown.
      if (kcal != null) (FontAwesomeIcons.fire, '~$kcal kcal'),
    ];

    // Which day of the rotation, by its name where it has one. A one-day plan
    // has no rotation to place it in, so it keeps the split's name. The
    // server calls days past a split's own names "Day N", which is no name:
    // "Day 4 of 4 · Day 4" would only say the number twice.
    final rotation = plan.days.length;
    final day = dayNo ?? 1;
    final dayName = plan.days
        .where((d) => d.dayNo == day)
        .map((d) => d.name)
        .firstOrNull;
    final split = describeSplit(plan.splitStyle);
    final eyebrow = rotation > 1
        ? [
            'Day $day of $rotation',
            if (dayName != null &&
                dayName.isNotEmpty &&
                !RegExp(r'^Day \d+$').hasMatch(dayName))
              dayName
            else
              split,
          ].where((part) => part.isNotEmpty).join(' · ')
        : split;
    // Three at most: a full-body day's every area is not a focus.
    final areas = regionsByCount(today.map((e) => e.muscleGroup))
        .take(3)
        .toList();

    return FsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            // At least the band the design draws; taller only when large
            // text needs it, so the chips never spill out of it.
            constraints: const BoxConstraints(minHeight: 116),
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
            child: Stack(
              children: [
                // Decoration only, faint at the band's right edge, behind
                // the words. Left out at large text, where the chips fill
                // the band and it would sit behind them as a smudge.
                if (MediaQuery.textScalerOf(context).scale(1) <= 1.3)
                  Positioned(
                    key: const Key('plan.watermark'),
                    right: 18,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Transform.rotate(
                        angle: -0.35,
                        child: FaIcon(
                          FontAwesomeIcons.dumbbell,
                          size: 56,
                          color: t.accent.withValues(alpha: 0.16),
                        ),
                      ),
                    ),
                  ),
                // Band-wide, and at least the band's height inside its
                // padding, so the words sit at its foot as they always have.
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 116 - 30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Two lines at most: today's day is worth reading
                          // whole, and the band grows to hold it.
                          FsEyebrow(eyebrow, maxLines: 2),
                          if (areas.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            // One phrase for a screen reader: "Back" alone
                            // could be taken for a way back.
                            Semantics(
                              container: true,
                              label:
                                  "Today's focus: ${_andList([for (final area in areas) area.label])}",
                              excludeSemantics: true,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final area in areas)
                                    _FocusChip(area, t: t),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final (icon, words) in meta)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FaIcon(icon, size: 11.5, color: t.text3),
                          const SizedBox(width: 5),
                          // Free to wrap, so a figure wider than a narrow
                          // card at large text breaks rather than overflows.
                          Flexible(
                            child: Text(
                              words,
                              style: TextStyle(fontSize: 12.5, color: t.text2),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
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

/// One area today works, on the band.
class _FocusChip extends StatelessWidget {
  const _FocusChip(this.area, {required this.t});

  final MuscleRegion area;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('plan.focus.${area.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(FsRadius.pill),
        border: Border.all(color: t.accentLine),
      ),
      child: Text(
        area.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: t.text,
        ),
      ),
    );
  }
}

/// "a", "a and b", "a, b and c".
String _andList(List<String> items) => items.length == 1
    ? items.single
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
