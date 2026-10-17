import '../../plans/domain/workout_plan.dart';
import '../domain/active_session.dart';

/// How an open workout is named wherever it shows up: Home's card, and the
/// question the review screen asks when one is in the way. One wording, so
/// the two never describe the same workout differently.
///
/// `planId`, not "has its own exercises": the server sends an empty
/// `exercises` list for plan-backed sessions by design, so an empty list
/// cannot tell a plan session from a manual one whose rows failed to load.
String openWorkoutTitle(ActiveSession session, WorkoutPlan? plan) =>
    session.planId == null
    ? 'Your own workout'
    : plan?.name ?? "Today's workout";

/// "2 exercises · 4 sets logged", or what is true instead.
String openWorkoutFacts(ActiveSession session, WorkoutPlan? plan) {
  final count = session.planId == null
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

/// "2 h ago", "yesterday": how long a workout has been open, so one left
/// behind days ago is recognisable as that. Null when the start time is
/// unknown, which says nothing rather than guessing.
///
/// "Opened", not "started": a workout with nothing logged reads "Not started
/// yet", and "started yesterday" beside it would contradict that.
String? openedAgo(DateTime? openedAt, DateTime now) {
  if (openedAt == null) return null;
  final gap = now.difference(openedAt);
  // A server clock a little ahead of the phone's puts the start in the
  // future, which is not "-3 min ago".
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inHours < 1) return '${gap.inMinutes} min ago';
  if (gap.inDays < 1) return '${gap.inHours} h ago';

  // Past a day, count calendar days: opened at 23:30 two nights ago is not
  // "yesterday" just because fewer than 48 hours have gone by. Rounded, not
  // floored, because a day that crosses a clock change is 23 or 25 hours.
  final opened = openedAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(opened.year, opened.month, opened.day);
  final days = (today.difference(day).inHours / 24).round();
  return days == 1 ? 'yesterday' : '$days days ago';
}
