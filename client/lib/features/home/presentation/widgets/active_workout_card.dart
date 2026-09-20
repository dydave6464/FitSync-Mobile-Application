import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../plans/domain/workout_plan.dart';
import '../../../sessions/domain/active_session.dart';

/// What Home shows while a workout is open, in the plan card's place.
///
/// Home used to render "Today's plan" and a Start button no matter what, so a
/// session left unfinished was invisible from the first screen of the app.
/// The only place it surfaced was the Train tab, and the only way to close it
/// was the logger's overflow menu -- so the usual way to discover it was the
/// manual picker refusing to start anything, which named a workout the user
/// had no memory of and offered no way to be rid of it.
///
/// It takes the plan card's place rather than sitting above it: there is one
/// workout at a time, so two cards each offering a way in would read as a
/// choice the server would refuse. The plan is not replaced, only covered --
/// finishing or discarding uncovers it again.
class ActiveWorkoutCard extends StatelessWidget {
  const ActiveWorkoutCard({
    super.key,
    required this.session,
    required this.plan,
    required this.onContinue,
    required this.onDiscard,
    this.discarding = false,
  });

  final ActiveSession session;

  /// The active plan, for naming a session that came from it. Null when there
  /// is no plan, which a hand-picked session does not need.
  final WorkoutPlan? plan;

  final VoidCallback onContinue;
  final VoidCallback onDiscard;
  final bool discarding;

  /// A session with no plan was picked by hand.
  ///
  /// `planId`, not "has its own exercises": the server sends an empty
  /// `exercises` list for plan-backed sessions by design, so an empty list
  /// cannot tell a plan session from a manual one whose rows failed to load.
  bool get _isManual => session.planId == null;

  String get _title =>
      _isManual ? 'Your own workout' : plan?.name ?? "Today's workout";

  /// "2 exercises · 4 sets logged", or what is true instead.
  String _facts() {
    final count = _isManual
        ? session.exercises.length
        : plan?.exercisesForDay(session.planDayNo).length ?? 0;
    final sets = session.completedSetCount;

    final parts = [
      if (count > 0) '$count ${count == 1 ? 'exercise' : 'exercises'}',
      // "0 sets logged" reads as a failure. A workout nobody has touched yet
      // has simply not been started, which is a different thing and the more
      // useful one to say -- it is the state a mis-tapped Start leaves.
      if (sets == 0)
        'Not started yet'
      else
        '$sets ${sets == 1 ? 'set' : 'sets'} logged',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return FsCard(
      key: const Key('home.inProgress'),
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 16, color: t.accent),
              const SizedBox(width: 6),
              const Expanded(child: FsEyebrow('Workout in progress')),
            ],
          ),
          const SizedBox(height: 8),
          Text(_title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(_facts(), style: TextStyle(fontSize: 12.5, color: t.text2)),
          const SizedBox(height: 14),
          // Wrap, not Row: at a large text scale two buttons side by side are
          // wider than a phone, and this card is the one place a user can
          // get out of a session they did not mean to start.
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FsButton(
                key: const Key('home.inProgress.continue'),
                label: 'Continue',
                small: true,
                icon: const Icon(Icons.play_arrow),
                onPressed: onContinue,
              ),
              TextButton(
                key: const Key('home.inProgress.discard'),
                onPressed: discarding ? null : onDiscard,
                child: Text(
                  'Discard',
                  style: TextStyle(fontSize: 13, color: t.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
