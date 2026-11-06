import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart'
    show describeError;

void main() {
  test('userMessage gives plain words for transport failures', () {
    expect(
      userMessage(
        const ApiException(
          'NETWORK_ERROR',
          'Could not reach http://x. adb reverse ...',
        ),
      ),
      "Couldn't reach FitSync. Check your connection and try again.",
    );
    expect(
      userMessage(const ApiException('INVALID_RESPONSE', 'non-JSON')),
      'Something went wrong on our side. Please try again.',
    );
    expect(
      userMessage(const ApiException('UNKNOWN_ERROR', 'The request failed.')),
      'Something went wrong on our side. Please try again.',
    );
    expect(
      userMessage(
        const ApiException('GOAL_ALREADY_MET', 'You already lift that.'),
      ),
      'You already lift that.',
    );
    expect(
      userMessage(StateError('x')),
      'Something went wrong. Please try again.',
    );
  });

  test('describeError says the same as userMessage', () {
    const offline = ApiException(
      'NETWORK_ERROR',
      'Could not reach http://x. adb reverse ...',
    );
    expect(describeError(offline), userMessage(offline));
    expect(describeError(StateError('x')), userMessage(StateError('x')));
  });

  test('details default to none and keep what the server sent', () {
    expect(const ApiException('X', 'y').details, isEmpty);
    expect(
      const ApiException(
        'INVALID_PROFILE_FIELD',
        'heightCm must be a number',
        details: [
          {'field': 'heightCm'},
        ],
      ).details.single['field'],
      'heightCm',
    );
  });
}
