/// The nutrition estimate the About step shows once it knows enough.
class DailyTargets {
  const DailyTargets({required this.kcal, required this.proteinG});

  final int kcal;
  final int proteinG;
}

/// Mifflin-St Jeor's sex constant. The equation has a term for two values and
/// no principled way to handle a third, which is why an unrecognised [sex]
/// yields no estimate at all.
const _sexConstants = <String, double>{'male': 5, 'female': -161};

/// Physical activity multipliers over BMR, one per `activity_level` ENUM
/// value. The standard ladder: desk-bound through twice-daily training.
const _multipliers = <String, double>{
  'sedentary': 1.2,
  'light': 1.375,
  'moderate': 1.55,
  'active': 1.725,
  'very_active': 1.9,
};

/// Grams of protein per kilogram of body weight.
///
/// The middle of the range the literature supports for people training for
/// hypertrophy or fat loss. It is deliberately not derived from the calorie
/// total: protein tracks lean mass, and scaling it with an activity
/// multiplier would tell a very active user to eat half again as much.
const _proteinPerKg = 1.6;

/// An estimated daily calorie and protein target, or null when the inputs do
/// not support one.
///
/// Null rather than a partial guess, exactly as `estimateSessionKcal` treats
/// an unknown body weight: every term here comes from something the user
/// answered, and substituting a population average for one of them produces a
/// confident number describing nobody.
///
/// [today] is injectable so a test's ages do not drift with the calendar.
DailyTargets? estimateDailyTargets({
  required String? sex,
  required String? dateOfBirth,
  required double? heightCm,
  required double? weightKg,
  required String? activityLevel,
  DateTime? today,
}) {
  final sexConstant = _sexConstants[sex];
  final multiplier = _multipliers[activityLevel];
  final born = dateOfBirth == null ? null : DateTime.tryParse(dateOfBirth);
  if (sexConstant == null ||
      multiplier == null ||
      born == null ||
      heightCm == null ||
      weightKg == null) {
    return null;
  }

  final now = today ?? DateTime.now();
  var age = now.year - born.year;
  // A birthday later this year has not happened yet, and Mifflin-St Jeor
  // charges five calories a year.
  final hadBirthday =
      now.month > born.month || (now.month == born.month && now.day >= born.day);
  if (!hadBirthday) age -= 1;

  final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + sexConstant;

  // Rounded off, because the precision is not there: the equation carries a
  // published error of roughly ±10%, so a figure like 2,322 would claim an
  // accuracy this cannot have.
  return DailyTargets(
    kcal: ((bmr * multiplier) / 50).round() * 50,
    proteinG: ((weightKg * _proteinPerKg) / 5).round() * 5,
  );
}
