/// Weight units.
///
/// Every weight FitSync stores is in kilograms -- `users.weight_kg`,
/// `users.goal_weight_kg`, `set_logs.weight_kg`, and everything the ML service
/// is fed. This is a display and input concern only. Converting at rest would
/// rewrite someone's whole logged history the moment they changed their mind,
/// and would desync the plan generator from the units its inputs are defined
/// in, so the conversion happens here at the edges instead.
enum WeightUnit {
  kg('kg'),
  lb('lb');

  const WeightUnit(this.api);

  /// The spelling the server stores and returns.
  final String api;

  /// Anything unrecognised reads as kilograms: the column is NOT NULL with a
  /// `kg` default, so an unknown value means a client newer than this one, and
  /// showing metric is a better failure than throwing on the profile.
  static WeightUnit fromApi(String? value) =>
      value == lb.api ? lb : kg;
}

/// One pound in kilograms, exactly, by international agreement since 1959.
const _kgPerLb = 0.45359237;

/// [kg] as [unit] displays it: a bare number, no unit suffix.
///
/// Kilograms keep two decimals and pounds one, both with trailing zeros
/// stripped -- `22.5` rather than `22.50`, `50` rather than `50.0`. A pound
/// figure is already ~2.2x finer per unit than a kilogram one, so a second
/// decimal buys nothing but noise on a phone.
/// [kg] as a plain number in [unit], unrounded.
///
/// For callers that format it themselves -- the session summary shows total
/// volume as a whole number, where [formatWeight]'s decimal would be noise.
double convertFromKg(double kg, WeightUnit unit) =>
    unit == WeightUnit.kg ? kg : kg / _kgPerLb;

String formatWeight(double kg, WeightUnit unit) {
  final value = convertFromKg(kg, unit);
  final fixed = value.toStringAsFixed(unit == WeightUnit.kg ? 2 : 1);
  // Guarded on the dot: `\.?0+$` against a string with no decimal point would
  // eat the significant zeros of "100" and leave "1".
  return fixed.contains('.') ? fixed.replaceFirst(RegExp(r'\.?0+$'), '') : fixed;
}

/// [kg] as [unit] displays it, with the unit named.
String formatWeightWithUnit(double kg, WeightUnit unit) =>
    '${formatWeight(kg, unit)} ${unit.api}';

/// What the user typed, in kilograms, ready to store.
///
/// Null for anything that is not a number, blank included: an empty weight
/// field means "not recorded", never zero.
double? parseWeight(String text, WeightUnit unit) {
  final typed = double.tryParse(text.trim());
  if (typed == null) return null;
  return unit == WeightUnit.kg ? typed : typed * _kgPerLb;
}
