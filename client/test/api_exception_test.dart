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

  // P-4: one definition of a failure that sending the same request again
  // may get past, for the automatic retry and the "Try again" action alike.
  group('isRetryableError', () {
    test('the transient codes: unreachable, server fault, garbled reply', () {
      for (final code in [
        'NETWORK_ERROR',
        'INTERNAL_ERROR',
        'INVALID_RESPONSE',
      ]) {
        expect(isRetryableError(ApiException(code, 'x')), isTrue, reason: code);
      }
    });

    test('a refusal the server named, or a bug, is not', () {
      for (final error in [
        const ApiException('ENTRY_NOT_FOUND', 'No such entry.'),
        const ApiException('INVALID_QUERY_PARAM', 'x'),
        const ApiException('UNKNOWN_ERROR', 'The request failed.'),
        const ApiException('CANCELLED', 'The request was cancelled.'),
        StateError('bug'),
      ]) {
        expect(isRetryableError(error), isFalse, reason: '$error');
      }
    });
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
