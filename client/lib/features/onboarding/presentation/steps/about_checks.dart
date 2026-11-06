import '../../../../core/api_exception.dart';
import '../../../../core/units.dart';
import 'about_step.dart';

/// The checks onboarding and Settings > Body metrics share around
/// [AboutStep]: a number that looks like a slip is queried once before it
/// is saved, and a field the server turned down is named the way the screen
/// names it, not by its API name.

/// Profile fields as the steps name them on screen.
const profileFieldNames = {
  'sex': 'sex',
  'dateOfBirth': 'date of birth',
  'heightCm': 'height',
  'weightKg': 'weight',
  'goalWeightKg': 'goal weight',
  'activityLevel': 'activity level',
  'fitnessLevel': 'experience',
  'trainingLocation': 'training location',
};

/// What to say under an About answer the server turned down.
const rejectedFieldMessage =
    "This can't be saved as it is. Check it and try again.";

/// The profile field a rejection points at, from the server's `details`.
/// Null for any other failure, or a `details` that names no field as text.
/// A weight refused as WEIGHT_OUT_OF_RANGE counts when its details name
/// the field.
String? rejectedProfileField(Object error) => switch (error) {
  ApiException(
    code: 'INVALID_PROFILE_FIELD' || 'WEIGHT_OUT_OF_RANGE',
    details: [{'field': final String field}, ...],
  ) =>
    field,
  _ => null,
};

/// The server's limit for a refused number, said under its card in the
/// unit on screen: "Enter a height between 50 and 275 cm.", or for a pound
/// user "Enter a weight between 45 and 1102 lb." -- whole numbers inside
/// the range, so either end typed back is accepted.
///
/// Read from `details[0]` (`{ field, min, max, unit }`) of an
/// INVALID_PROFILE_FIELD or WEIGHT_OUT_OF_RANGE. Null when the details carry
/// no range -- an older server -- and the caller falls back to
/// [rejectedFieldMessage].
String? rangeFieldMessage(Object error, WeightUnit unit) {
  if (error is! ApiException ||
      (error.code != 'INVALID_PROFILE_FIELD' &&
          error.code != 'WEIGHT_OUT_OF_RANGE')) {
    return null;
  }
  final range = switch (error.details) {
    [
      {
        'field': final String field,
        'min': final num min,
        'max': final num max,
        'unit': final String sent,
      },
      ...,
    ] =>
      (field: field, min: min, max: max, unit: sent),
    _ => null,
  };
  final name = profileFieldNames[range?.field];
  if (range == null || name == null) return null;
  final (min, max, suffix) = switch (range.unit) {
    'cm' => (_plain(range.min), _plain(range.max), 'cm'),
    // Rounded inward, never to the nearest: 20 kg is 44.09 lb, and a "44"
    // typed back reads as 19.96 kg, which the server refuses again. So the
    // low end rounds up (45) and the high end down (1102).
    'kg' => (
      convertFromKg(range.min.toDouble(), unit).ceil().toString(),
      convertFromKg(range.max.toDouble(), unit).floor().toString(),
      unit.api,
    ),
    _ => (null, null, null),
  };
  if (suffix == null) return null;
  return 'Enter a $name between $min and $max $suffix.';
}

/// 50 as "50", 49.5 as "49.5".
String _plain(num n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toString();

/// A failure in words a user can act on: [userMessage], except for the
/// server's rejections of a profile answer, whose message names the API
/// field ("goalWeightKg must be ...") rather than anything on screen. The
/// field it sends in `details` is named the way the step names it instead.
String plainProfileError(Object error) {
  final field = rejectedProfileField(error);
  if (error is! ApiException ||
      (error.code != 'INVALID_PROFILE_FIELD' && field == null)) {
    return userMessage(error);
  }
  final name = profileFieldNames[field];
  return name == null
      ? "One of these answers can't be saved as it is. Check it and try "
            'again.'
      : "Your $name can't be saved as it is. Check it and try again.";
}

/// The line by the button when [fields] (API names) look like slips:
/// "Check your height. If it's right, tap Continue again."
String rangeQueryMessage(Iterable<String> fields, {required String button}) {
  final names = [for (final field in fields) profileFieldNames[field]!];
  final list = names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  final pronoun = names.length < 2 ? "it's" : "they're";
  return 'Check your $list. If $pronoun right, tap $button again.';
}

/// One About answer by its API field name.
Object? aboutValue(AboutAnswers about, String field) => switch (field) {
  'sex' => about.sex,
  'dateOfBirth' => about.dateOfBirth,
  'heightCm' => about.heightCm,
  'weightKg' => about.weightKg,
  'goalWeightKg' => about.goalWeightKg,
  'activityLevel' => about.activityLevel,
  _ => null,
};

/// Whether every field in [fields] holds the same answer in [a] and [b].
bool sameAboutAnswers(
  Iterable<String> fields,
  AboutAnswers a,
  AboutAnswers b,
) => fields.every((field) => aboutValue(a, field) == aboutValue(b, field));

/// The messages in [errors] whose answer is still the one [queried] held:
/// an answer changed since loses its message.
Map<String, String> standingFieldErrors(
  Map<String, String> errors,
  AboutAnswers queried,
  AboutAnswers now,
) => {
  for (final MapEntry(:key, value: message) in errors.entries)
    if (aboutValue(queried, key) == aboutValue(now, key)) key: message,
};
