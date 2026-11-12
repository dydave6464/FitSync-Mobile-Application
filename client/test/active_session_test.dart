import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';

void main() {
  group('inProgressSessionId', () {
    test('reads the open session off a SESSION_IN_PROGRESS refusal', () {
      expect(
        inProgressSessionId(
          const ApiException(
            'SESSION_IN_PROGRESS',
            'You have a workout in progress.',
            details: [
              {'sessionId': 41, 'startedAt': '2026-11-06T01:02:03.000Z'},
            ],
          ),
        ),
        41,
      );
    });

    test('is null when an older server sends no details', () {
      expect(
        inProgressSessionId(
          const ApiException('SESSION_IN_PROGRESS', 'Finish or discard.'),
        ),
        isNull,
      );
    });

    test('is null for any other refusal', () {
      expect(
        inProgressSessionId(
          const ApiException(
            'CUSTOM_PLAN_WOULD_BE_LOST',
            'Replace it?',
            details: [
              {'sessionId': 41},
            ],
          ),
        ),
        isNull,
      );
      expect(inProgressSessionId(StateError('boom')), isNull);
    });
  });
}
