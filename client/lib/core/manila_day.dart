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
