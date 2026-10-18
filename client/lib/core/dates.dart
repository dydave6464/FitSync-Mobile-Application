/// Short date words for charts and their tooltips: "Mon", "Sep 20".
///
/// English and fixed, like every other string in the app; there is no locale
/// to follow yet.
const monthShort = [
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

/// Monday first, matching [DateTime.weekday] (1 is Monday).
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Sep 20".
String shortDate(DateTime day) => '${monthShort[day.month - 1]} ${day.day}';
