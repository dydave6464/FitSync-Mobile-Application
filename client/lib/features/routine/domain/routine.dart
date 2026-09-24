/// `06:30` -> `6:30 AM`. The server speaks 24-hour `HH:MM`.
String formatClock(String hhmm) {
  final hour = int.parse(hhmm.substring(0, 2));
  final minutes = hhmm.substring(3, 5);
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:$minutes ${hour < 12 ? 'AM' : 'PM'}';
}

/// A repeating habit and today's tick, as GET /routine/today lists it.
class Habit {
  const Habit({
    required this.habitId,
    required this.title,
    required this.time,
    required this.durationMin,
    required this.weekdays,
    required this.done,
  });

  final int habitId;
  final String title;

  /// `HH:MM`, 24-hour, or null for "any time".
  final String? time;
  final int? durationMin;

  /// 1 = Monday .. 7 = Sunday.
  final List<int> weekdays;
  final bool done;

  /// "6:30 AM · 8 min", either half, or empty.
  String get subtitle => [
    if (time != null) formatClock(time!),
    if (durationMin != null) '$durationMin min',
  ].join(' · ');

  Habit withDone(bool value) => Habit(
    habitId: habitId,
    title: title,
    time: time,
    durationMin: durationMin,
    weekdays: weekdays,
    done: value,
  );

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    habitId: json['habitId'] as int,
    title: json['title'] as String,
    time: json['time'] as String?,
    durationMin: json['durationMin'] as int?,
    weekdays: (json['weekdays'] as List<dynamic>).cast<int>(),
    done: json['done'] as bool,
  );
}

/// Today's automatic workout item. Done means a session was completed today;
/// it is never ticked by hand.
class RoutineWorkout {
  const RoutineWorkout({required this.title, required this.done});

  final String title;
  final bool done;

  factory RoutineWorkout.fromJson(Map<String, dynamic> json) => RoutineWorkout(
    title: json['title'] as String,
    done: json['done'] as bool,
  );
}

/// One row of the checklist, in the order the screen and the Home card show.
sealed class RoutineEntry {
  const RoutineEntry();
  String get title;
  bool get done;
}

class HabitEntry extends RoutineEntry {
  const HabitEntry(this.habit);
  final Habit habit;
  @override
  String get title => habit.title;
  @override
  bool get done => habit.done;
}

class WorkoutEntry extends RoutineEntry {
  const WorkoutEntry(this.workout);
  final RoutineWorkout workout;
  @override
  String get title => workout.title;
  @override
  bool get done => workout.done;
}

/// The tie-break key for a title collision in [RoutineDay.entries]: a
/// habit's own id, or a value past any real habit id for the workout item,
/// so the workout always comes last on a tie.
int _tieBreak(RoutineEntry e) => switch (e) {
  HabitEntry(:final habit) => habit.habitId,
  WorkoutEntry() => 1 << 30,
};

class RoutineDay {
  const RoutineDay({
    required this.date,
    required this.habits,
    required this.workout,
  });

  /// `YYYY-MM-DD`, the server's today.
  final String date;

  /// Server order: timed habits by time, then untimed ones by title.
  final List<Habit> habits;
  final RoutineWorkout? workout;

  /// Timed habits first, as the server orders them; then the untimed habits
  /// and the workout item, which has no time, by title. A tied title falls
  /// back to habit id, oldest first, so the order does not reshuffle between
  /// loads; the workout item sorts after every habit it ties with, since a
  /// habit is something the person named and the workout is not.
  List<RoutineEntry> get entries {
    final untimed =
        <RoutineEntry>[
          for (final h in habits)
            if (h.time == null) HabitEntry(h),
          if (workout != null) WorkoutEntry(workout!),
        ]..sort((a, b) {
          final byTitle = a.title.toLowerCase().compareTo(
            b.title.toLowerCase(),
          );
          return byTitle != 0 ? byTitle : _tieBreak(a).compareTo(_tieBreak(b));
        });
    return [
      for (final h in habits)
        if (h.time != null) HabitEntry(h),
      ...untimed,
    ];
  }

  int get total => habits.length + (workout == null ? 0 : 1);

  int get done =>
      habits.where((h) => h.done).length + (workout?.done == true ? 1 : 0);

  RoutineDay withHabitDone(int habitId, bool value) => RoutineDay(
    date: date,
    habits: [
      for (final h in habits) h.habitId == habitId ? h.withDone(value) : h,
    ],
    workout: workout,
  );

  factory RoutineDay.fromJson(Map<String, dynamic> json) => RoutineDay(
    date: json['date'] as String,
    habits: (json['habits'] as List<dynamic>)
        .map((h) => Habit.fromJson(h as Map<String, dynamic>))
        .toList(),
    workout: json['workout'] == null
        ? null
        : RoutineWorkout.fromJson(json['workout'] as Map<String, dynamic>),
  );
}

/// What the habit sheet sends, for both add and edit. Every field is sent,
/// null included: on PATCH, a null time or duration clears it.
class HabitDraft {
  const HabitDraft({
    required this.title,
    required this.time,
    required this.durationMin,
    required this.weekdays,
  });

  final String title;
  final String? time;
  final int? durationMin;
  final List<int> weekdays;

  Map<String, dynamic> toJson() => {
    'title': title,
    'time': time,
    'durationMin': durationMin,
    'weekdays': weekdays,
  };
}
