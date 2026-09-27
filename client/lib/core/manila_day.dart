/// `YYYY-MM-DD` in Manila for [instant].
///
/// The day the server calls "today": every database connection runs at
/// +08:00, so CURDATE() turns over at midnight in Manila. Computed from the
/// instant rather than the device's own zone, so a phone set to another zone
/// still agrees with the server about which day it is. The Philippines keeps
/// no daylight saving, so the fixed offset is always exact.
String manilaDayOf(DateTime instant) {
  final manila = instant.toUtc().add(const Duration(hours: 8));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${manila.year}-${pad(manila.month)}-${pad(manila.day)}';
}

/// [hhmm] (`HH:MM`, 24-hour) on the Manila calendar day [day] -- a
/// UTC-midnight DateTime carrying only the date -- as a UTC instant. The
/// reminder planner and the Schedule's reminder lines both use it, so the
/// Schedule never promises a time the phone would not schedule.
DateTime manilaInstant(DateTime day, String hhmm) => DateTime.utc(
  day.year,
  day.month,
  day.day,
  int.parse(hhmm.substring(0, 2)) - 8,
  int.parse(hhmm.substring(3, 5)),
);
