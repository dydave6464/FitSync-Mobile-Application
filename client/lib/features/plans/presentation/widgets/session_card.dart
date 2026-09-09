import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/workout_plan.dart';

/// The hero of the Plan tab: what today's session is, and the way into it.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.plan,
    required this.hasActiveSession,
    required this.onStart,
    this.starting = false,
    this.dayNo,
  });

  final WorkoutPlan plan;

  /// Which rotation day this card is describing — the caller works it out
  /// with [WorkoutPlan.todayDayNo], since it depends on how many sessions
  /// are already complete this week. Null reads as day 1, which is what a
  /// plan from a server predating per-day plans is.
  final int? dayNo;

  /// True when a session is already in progress — the button then resumes it
  /// rather than starting a second.
  final bool hasActiveSession;

  final VoidCallback onStart;
  final bool starting;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    // Today's day, not the whole rotation. This card sits directly above the
    // Plan tab's exercise list, which shows one day: on a three-day rotation
    // it read "24 exercises" over a list of eight. exercisesForDay is the
    // single home of that filtering.
    final count = plan.exercisesForDay(dayNo).length;

    final facts = [
      describeSplit(plan.splitStyle),
      '${plan.daysPerWeek} days a week',
      '$count ${count == 1 ? 'exercise' : 'exercises'}',
      '${plan.sessionLengthMin} min',
    ].where((part) => part.isNotEmpty).join(' · ');

    return FsCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                // Not FsEyebrow: that widget forces its text to uppercase,
                // which would render "WEEK 1" instead of the wording the
                // card is meant to show. The eyebrow *style* -- mono, wide
                // tracking -- still applies via fsEyebrow(t).
                child: Text('Week ${plan.weekNo}', style: fsEyebrow(t)),
              ),
              if (hasActiveSession) const FsTag('In progress'),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(facts, style: TextStyle(fontSize: 12.5, color: t.text2)),
          const SizedBox(height: 16),
          FsButton(
            key: const Key('session.start'),
            label: hasActiveSession ? 'Resume session' : 'Start session',
            small: true,
            // Null while the request is in flight: tapping twice would be
            // harmless server-side (POST /sessions is idempotent) but would
            // push the logger twice.
            onPressed: starting ? null : onStart,
          ),
        ],
      ),
    );
  }
}
