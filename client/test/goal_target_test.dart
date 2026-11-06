import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/streaks/presentation/goal_target.dart';

void main() {
  group('goalTargetError', () {
    test('a blank or zero target asks for one', () {
      expect(goalTargetError('', WeightUnit.kg, null), (
        null,
        'Enter a target weight.',
      ));
      expect(goalTargetError('0', WeightUnit.kg, null), (
        null,
        'Enter a target weight.',
      ));
    });

    test('a target outside the server range names it in the unit', () {
      expect(goalTargetError('1000', WeightUnit.kg, null), (
        null,
        'Enter a target between 0.5 kg and 999.99 kg.',
      ));
      expect(goalTargetError('3000', WeightUnit.lb, null), (
        null,
        'Enter a target between ${formatWeightWithUnit(0.5, WeightUnit.lb)} '
            'and ${formatWeightWithUnit(999.99, WeightUnit.lb)}.',
      ));
    });

    test('a target at or below the best is refused in the unit', () {
      expect(goalTargetError('52.5', WeightUnit.kg, 52.5), (
        null,
        'Your best is already 52.5 kg.',
      ));
      // 135 lb rounds to the 61.23 kg that would be sent.
      expect(goalTargetError('135', WeightUnit.lb, 61.23), (
        null,
        'Your best is already ${formatWeightWithUnit(61.23, WeightUnit.lb)}.',
      ));
    });

    test('a good target comes back in kilograms, to two decimals', () {
      expect(goalTargetError('60', WeightUnit.kg, 52.5), (60.0, null));
      expect(goalTargetError('135', WeightUnit.lb, null), (61.23, null));
    });
  });

  group('goalErrorMessage', () {
    test("GOAL_ALREADY_MET with the best says it in the user's unit", () {
      const error = ApiException(
        'GOAL_ALREADY_MET',
        'Your best is already 60 kg.',
        details: [
          {'field': 'targetKg', 'bestKg': 60},
        ],
      );
      expect(
        goalErrorMessage(error, WeightUnit.lb),
        'Your best is already 132.3 lb.',
      );
    });

    test('GOAL_ALREADY_MET without the best keeps the server message', () {
      const error = ApiException(
        'GOAL_ALREADY_MET',
        'Your best is already 60 kg.',
      );
      expect(
        goalErrorMessage(error, WeightUnit.lb),
        'Your best is already 60 kg.',
      );
    });

    test("TARGET_INVALID names the range in the user's unit", () {
      const error = ApiException(
        'TARGET_INVALID',
        'targetKg must be a number from 0.5 to 999.99.',
        details: [
          {'field': 'targetKg'},
        ],
      );
      expect(
        goalErrorMessage(error, WeightUnit.kg),
        'Enter a target between 0.5 kg and 999.99 kg.',
      );
    });

    test('anything else is userMessage', () {
      const network = ApiException('NETWORK_ERROR', 'http://10.0.2.2 down');
      expect(goalErrorMessage(network, WeightUnit.kg), userMessage(network));
      final bug = StateError('x');
      expect(goalErrorMessage(bug, WeightUnit.kg), userMessage(bug));
    });
  });
}
