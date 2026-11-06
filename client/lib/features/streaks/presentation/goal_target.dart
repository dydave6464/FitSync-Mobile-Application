import '../../../core/api_exception.dart';
import '../../../core/units.dart';

/// The server's range for a goal's target, in kilograms (DECIMAL 6,2 and
/// ck_lift_goals_target).
const _minKg = 0.5;
const _maxKg = 999.99;

String _rangeMessage(WeightUnit unit) =>
    'Enter a target between ${formatWeightWithUnit(_minKg, unit)} and '
    '${formatWeightWithUnit(_maxKg, unit)}.';

String _bestMessage(double bestKg, WeightUnit unit) =>
    'Your best is already ${formatWeightWithUnit(bestKg, unit)}.';

/// A typed target checked as the server will check it, for the add-goal
/// sheet and the goal sheet's Change target alike: the kilograms to send,
/// or why not, in the user's [unit].
///
/// Rounded to what the body carries (DECIMAL 6,2) before comparing with
/// [bestKg]: a target that only beats the best before rounding would pass
/// here, then be refused by the server on the rounded value.
(double?, String?) goalTargetError(
  String text,
  WeightUnit unit,
  double? bestKg,
) {
  final kg = parseWeight(text, unit);
  if (kg == null) return (null, 'Enter a target weight.');
  final sendKg = double.parse(kg.toStringAsFixed(2));
  if (sendKg <= 0) return (null, 'Enter a target weight.');
  if (sendKg < _minKg || sendKg > _maxKg) return (null, _rangeMessage(unit));
  if (bestKg != null && sendKg <= bestKg) {
    return (null, _bestMessage(bestKg, unit));
  }
  return (sendKg, null);
}

/// A goal save's failure in the user's [unit], with the same words as the
/// checks in [goalTargetError], so the user reads one wording whichever
/// side caught it. The server's own sentence is in kilograms.
String goalErrorMessage(Object error, WeightUnit unit) {
  final best = goalErrorBestKg(error);
  if (best != null) return _bestMessage(best, unit);
  return switch (error) {
    ApiException(code: 'TARGET_INVALID') => _rangeMessage(unit),
    _ => userMessage(error),
  };
}

/// The best a GOAL_ALREADY_MET refusal carries, in kilograms, or null when
/// it carries none (an older server).
double? goalErrorBestKg(Object error) => switch (error) {
  ApiException(code: 'GOAL_ALREADY_MET', :final details)
      when details.isNotEmpty && details.first['bestKg'] is num =>
    (details.first['bestKg'] as num).toDouble(),
  _ => null,
};
