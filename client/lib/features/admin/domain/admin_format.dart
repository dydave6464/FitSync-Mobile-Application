import '../../../core/dates.dart' show monthShort;
import '../../../core/numbers.dart' show groupThousands;

/// Words and figures for the admin screens: pesos, signed changes, days.
///
/// A negative figure leads with U+2212, the real minus sign, rather than a
/// hyphen: it lines up with "+" and reads as "minus" to a screen reader.
const _minus = '−';

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

/// "₱1,788", "₱1,788.50", "₱0", "−₱249". Whole pesos carry no decimals;
/// anything with centavos carries two.
String formatPhp(double php) {
  final cents = (php.abs() * 100).round();
  final whole = groupThousands((cents ~/ 100).toDouble());
  final rest = cents % 100;
  final amount = rest == 0
      ? '₱$whole'
      : '₱$whole.${rest.toString().padLeft(2, '0')}';
  return cents > 0 && php < 0 ? '$_minus$amount' : amount;
}

/// "+3", "−2", "0".
String signedCount(int delta) {
  final digits = groupThousands(delta.abs().toDouble());
  if (delta > 0) return '+$digits';
  if (delta < 0) return '$_minus$digits';
  return digits;
}

/// "+₱747", "−₱249", "₱0".
String signedPhp(double delta) {
  final amount = formatPhp(delta);
  return delta > 0 && (delta * 100).round() > 0 ? '+$amount' : amount;
}

DateTime _day(String ymd) {
  final parts = ymd.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

/// How long ago a trainee last logged anything, next to [today] (both
/// Manila `YYYY-MM-DD`): "active today", "active 12 d ago", "not active yet".
String lastActiveLabel(String? day, String today) {
  if (day == null) return 'not active yet';
  final behind = _day(today).difference(_day(day)).inDays;
  return behind <= 0 ? 'active today' : 'active $behind d ago';
}

/// "2026-11" → "November 2026".
String monthLabel(String ym) {
  final parts = ym.split('-');
  return '${_monthNames[int.parse(parts[1]) - 1]} ${parts[0]}';
}

/// "2026-11-05" → "Joined 5 Nov 2026".
String joinedLabel(String day) {
  final d = _day(day);
  return 'Joined ${d.day} ${monthShort[d.month - 1]} ${d.year}';
}

/// An ad's run, both days included (Manila `YYYY-MM-DD`): "1–30 Nov"
/// inside one month, "28 Oct – 3 Nov" across two, "7 Nov" for one day, and
/// with the years when the run crosses into a new one.
String runLabel(String startsOn, String endsOn) {
  final start = _day(startsOn);
  final end = _day(endsOn);
  String day(DateTime d, {bool year = false}) =>
      '${d.day} ${monthShort[d.month - 1]}${year ? ' ${d.year}' : ''}';
  if (start == end) return day(start);
  if (start.year != end.year) {
    return '${day(start, year: true)} – ${day(end, year: true)}';
  }
  if (start.month == end.month) return '${start.day}–${day(end)}';
  return '${day(start)} – ${day(end)}';
}

/// "1,204 views · 37 taps", "1 view · 1 tap".
String adCountsLabel(int views, int taps) {
  String counted(int n, String word) =>
      '${groupThousands(n.toDouble())} $word${n == 1 ? '' : 's'}';
  return '${counted(views, 'view')} · ${counted(taps, 'tap')}';
}

/// The nine `foods.food_type` values in the server's order
/// (`FOOD_TYPES` in server/src/db/foods.js), each in plain words.
const foodTypeLabels = {
  'home': 'Home-cooked',
  'fruit_veg': 'Fruit & veg',
  'bread_kakanin': 'Bread & kakanin',
  'canned_instant': 'Canned & instant',
  'drink': 'Drink',
  'street': 'Street food',
  'snack_sweet': 'Snack & sweet',
  'fast_food': 'Fast food',
  'condiment': 'Condiment',
};

/// A server media path (`/storage/...`) joined to the server's address with
/// exactly one slash between them, as `ExerciseThumb` joins its artwork.
String mediaUrl(String baseUrl, String path) =>
    '$baseUrl${path.startsWith('/') ? '' : '/'}$path';
