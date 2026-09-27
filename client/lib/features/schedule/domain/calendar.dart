/// A day's workout on the Schedule: done on a past day, planned or done
/// today, planned after.
class CalendarWorkout {
  const CalendarWorkout({required this.title, required this.done});

  /// The plan's name, else `Workout`.
  final String title;
  final bool done;

  factory CalendarWorkout.fromJson(Map<String, dynamic> json) =>
      CalendarWorkout(
        title: json['title'] as String,
        done: json['done'] as bool,
      );
}

/// A habit on a day: ticked on a past day, due (and maybe ticked) today,
/// due after.
class CalendarHabit {
  const CalendarHabit({
    required this.habitId,
    required this.title,
    required this.time,
    required this.done,
  });

  final int habitId;
  final String title;

  /// `HH:MM`, 24-hour, or null for "any time".
  final String? time;
  final bool done;

  factory CalendarHabit.fromJson(Map<String, dynamic> json) => CalendarHabit(
    habitId: json['habitId'] as int,
    title: json['title'] as String,
    time: json['time'] as String?,
    done: json['done'] as bool,
  );
}

/// One date of GET /calendar. Habits arrive in the routine's order: timed by
/// time, then untimed by title.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.workout,
    required this.habits,
  });

  /// `YYYY-MM-DD`, Manila.
  final String date;
  final CalendarWorkout? workout;
  final List<CalendarHabit> habits;

  factory CalendarDay.fromJson(Map<String, dynamic> json) => CalendarDay(
    date: json['date'] as String,
    workout: json['workout'] == null
        ? null
        : CalendarWorkout.fromJson(json['workout'] as Map<String, dynamic>),
    habits: (json['habits'] as List<dynamic>)
        .map((h) => CalendarHabit.fromJson(h as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// GET /calendar: every date of the range, oldest first, and the server's
/// today, which decides what counts as past.
class CalendarRange {
  const CalendarRange({required this.today, required this.days});

  final String today;
  final List<CalendarDay> days;

  factory CalendarRange.fromJson(Map<String, dynamic> json) => CalendarRange(
    today: json['today'] as String,
    days: (json['days'] as List<dynamic>)
        .map((d) => CalendarDay.fromJson(d as Map<String, dynamic>))
        .toList(growable: false),
  );
}
