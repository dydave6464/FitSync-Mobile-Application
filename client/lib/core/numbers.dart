/// 8053.0 -> "8,053". Whole units only: a gram or an ounce of barbell volume
/// is noise, and the separator is what makes a five-figure total readable at
/// a glance. Shared by Progress, Recovery and Nutrition, so it lives here
/// rather than in any one of their screens.
String groupThousands(double value) {
  final digits = value.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
