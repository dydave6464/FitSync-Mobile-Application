import '../../reminders/domain/reminders.dart';
import '../../routine/domain/routine.dart' show formatClock;
import 'calendar.dart';

typedef YearMonth = ({int year, int month});

/// `YYYY-MM-DD` as a UTC midnight, so adding days never meets a
/// daylight-saving hour.
DateTime _parse(String date) => DateTime.utc(
  int.parse(date.substring(0, 4)),
  int.parse(date.substring(5, 7)),
  int.parse(date.substring(8, 10)),
);

String _format(DateTime d) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${pad(d.month)}-${pad(d.day)}';
}

String addDays(String date, int days) =>
    _format(_parse(date).add(Duration(days: days)));

YearMonth monthOf(String date) => (
  year: int.parse(date.substring(0, 4)),
  month: int.parse(date.substring(5, 7)),
);

YearMonth shiftMonth(YearMonth m, int delta) {
  final index = m.year * 12 + (m.month - 1) + delta;
  return (year: index ~/ 12, month: index % 12 + 1);
}

/// The 42 dates of [m]'s grid: six Monday-first weeks, starting on the
/// Monday on or before the 1st. Always six rows, so the grid never changes
/// height between months. At most 62 days, so one request covers it.
List<String> monthGridDates(YearMonth m) {
  final first = DateTime.utc(m.year, m.month, 1);
  final start = first.subtract(Duration(days: first.weekday - 1));
  return [for (var i = 0; i < 42; i++) _format(start.add(Duration(days: i)))];
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `September 2026`.
String formatMonthTitle(YearMonth m) => '${_monthNames[m.month - 1]} ${m.year}';

/// `2026-09-24` -> `Thu 24 Sep`.
String formatDayLabel(String date) {
  final d = _parse(date);
  return '${_weekdayShort[d.weekday - 1]} ${d.day} ${_monthShort[d.month - 1]}';
}

/// `Today`, `Tomorrow`, else [formatDayLabel].
String relativeDayLabel(String date, String today) {
  if (date == today) return 'Today';
  if (date == addDays(today, 1)) return 'Tomorrow';
  return formatDayLabel(date);
}

/// One row under the grid: a habit, or the day's workout.
class ScheduleItem {
  const ScheduleItem({
    required this.date,
    required this.title,
    required this.time,
    required this.done,
    required this.isWorkout,
  });

  final String date;

  /// The habit's title, or the workout's plan name.
  final String title;

  /// `HH:MM` for a timed habit; null for an untimed one and the workout.
  final String? time;
  final bool done;
  final bool isWorkout;
}

/// [day]'s items in the routine's order: timed habits by time, the workout,
/// then untimed habits -- the server already sends habits in that order.
List<ScheduleItem> dayItems(CalendarDay day) {
  ScheduleItem habit(CalendarHabit h) => ScheduleItem(
    date: day.date,
    title: h.title,
    time: h.time,
    done: h.done,
    isWorkout: false,
  );
  final workout = day.workout;
  return [
    for (final h in day.habits.where((h) => h.time != null)) habit(h),
    if (workout != null)
      ScheduleItem(
        date: day.date,
        title: workout.title,
        time: null,
        done: workout.done,
        isWorkout: true,
      ),
    for (final h in day.habits.where((h) => h.time == null)) habit(h),
  ];
}

/// Every item not yet done, from the range's today on, by date then in
/// [dayItems] order.
List<ScheduleItem> upcomingItems(CalendarRange range) => [
  for (final day in range.days)
    if (day.date.compareTo(range.today) >= 0)
      ...dayItems(day).where((i) => !i.done),
];

/// `Stretch · 6:30 AM`, `Walk · Any time`, `Workout · Upper/Lower`.
String itemLine(ScheduleItem item) {
  if (item.isWorkout) return 'Workout · ${item.title}';
  final time = item.time;
  return '${item.title} · ${time == null ? 'Any time' : formatClock(time)}';
}

/// `Today · Stretch · 6:30 AM`.
String upcomingLine(ScheduleItem item, String today) =>
    '${relativeDayLabel(item.date, today)} · ${itemLine(item)}';

/// The master switch (the profile's notificationsEnabled) and the reminder
/// settings.
typedef ReminderContext = ({bool masterOn, ReminderSettings settings});

/// What will remind about [item], or null when nothing will. Decided by the
/// settings alone, as the phone schedules them: a timed habit with habit
/// reminders on, or the workout with workout reminders on.
String? reminderLine(ScheduleItem item, ReminderContext r) {
  if (!r.masterOn) return null;
  final s = r.settings;
  if (item.isWorkout) {
    return s.workoutEnabled
        ? 'Reminder at ${formatClock(s.workoutTime)}'
        : null;
  }
  if (!s.habitsEnabled || item.time == null) return null;
  return s.habitLeadMin == 0
      ? 'Reminder at the time'
      : 'Reminder ${s.habitLeadMin} min before';
}

/// The Upcoming header's tag: on when the master switch and at least one of
/// the three reminders are.
bool remindersOn(ReminderContext r) =>
    r.masterOn &&
    (r.settings.habitsEnabled ||
        r.settings.workoutEnabled ||
        r.settings.checkinEnabled);

/// A dot under a grid day: filled for done, a ring for planned or due.
enum DotState { none, planned, done }

DotState workoutDot(CalendarDay day) {
  final workout = day.workout;
  if (workout == null) return DotState.none;
  return workout.done ? DotState.done : DotState.planned;
}

DotState habitsDot(CalendarDay day) {
  if (day.habits.isEmpty) return DotState.none;
  return day.habits.any((h) => h.done) ? DotState.done : DotState.planned;
}
