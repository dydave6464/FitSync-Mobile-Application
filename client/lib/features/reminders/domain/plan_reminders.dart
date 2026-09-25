import '../../../core/manila_day.dart';
import '../../routine/domain/routine.dart';
import 'reminders.dart';

/// Under iOS's limit of 64 pending notifications.
const maxReminders = 60;

const _manilaOffset = Duration(hours: 8);

/// [hhmm] on the Manila calendar day [day] (a UTC-midnight DateTime carrying
/// only the date), as a UTC instant.
DateTime _atManila(DateTime day, String hhmm) => DateTime.utc(
  day.year,
  day.month,
  day.day,
  int.parse(hhmm.substring(0, 2)),
  int.parse(hhmm.substring(3, 5)),
).subtract(_manilaOffset);

/// The reminders for today and the next six days (Manila), soonest first,
/// capped at [maxReminders]. One-offs rather than repeating rules, so what is
/// already done today can be skipped; the caller replaces the whole set
/// whenever anything relevant changes.
///
/// [planName] null means no active plan, so no workout reminders. Workout
/// days follow the routine's own rule: every day when no training days are
/// chosen.
List<PlannedReminder> planReminders({
  required ReminderSettings settings,
  required bool masterOn,
  required List<Habit> habits,
  required List<int> trainingDays,
  required String? planName,
  required TodayDone done,
  required DateTime now,
}) {
  if (!masterOn) return const [];

  final parts = manilaDayOf(now).split('-').map(int.parse).toList();
  final today = DateTime.utc(parts[0], parts[1], parts[2]);
  final candidates = <PlannedReminder>[];

  void add(DateTime at, String title, String body, String payload) =>
      candidates.add(
        PlannedReminder(
          id: 0,
          at: at,
          title: title,
          body: body,
          payload: payload,
        ),
      );

  for (var i = 0; i < 7; i++) {
    final day = today.add(Duration(days: i));
    final weekday = day.weekday;
    final isToday = i == 0;

    if (settings.habitsEnabled) {
      for (final h in habits) {
        final time = h.time;
        if (time == null || !h.weekdays.contains(weekday)) continue;
        if (isToday && done.habitIds.contains(h.habitId)) continue;
        add(
          _atManila(
            day,
            time,
          ).subtract(Duration(minutes: settings.habitLeadMin)),
          h.title,
          settings.habitLeadMin == 0 ? 'Now' : 'At ${formatClock(time)}',
          'routine',
        );
      }
    }

    final trainingDay = trainingDays.isEmpty || trainingDays.contains(weekday);
    if (settings.workoutEnabled &&
        planName != null &&
        trainingDay &&
        !(isToday && done.workout)) {
      add(
        _atManila(day, settings.workoutTime),
        'Workout today',
        planName,
        'routine',
      );
    }

    if (settings.checkinEnabled && !(isToday && done.checkin)) {
      add(
        _atManila(day, settings.checkinTime),
        'Morning check-in',
        'How did you sleep?',
        'recovery',
      );
    }
  }

  final upcoming = candidates.where((r) => r.at.isAfter(now)).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  return [
    for (final (i, r) in upcoming.take(maxReminders).indexed)
      PlannedReminder(
        id: i,
        at: r.at,
        title: r.title,
        body: r.body,
        payload: r.payload,
      ),
  ];
}
