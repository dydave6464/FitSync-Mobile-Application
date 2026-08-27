import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';

/// A repository double that always fails with a given [ApiException] and
/// counts how many times [byId] actually ran, so a test can prove whether a
/// permanent failure was retried behind the scenes.
class _FailingRepository implements ExerciseRepository {
  _FailingRepository(this.error);

  final ApiException error;
  int byIdCalls = 0;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExerciseDetail> byId(int id) async {
    byIdCalls++;
    throw error;
  }

  @override
  Future<ExercisePage> list({
    String? muscleGroup,
    String? equipment,
    int page = 1,
    int limit = 20,
  }) =>
      throw UnimplementedError();

  @override
  Future<ExerciseFilters> filters() => throw UnimplementedError();
}

void main() {
  // Riverpod's ProviderContainer.defaultRetry retries any error that is not
  // a ProviderException or an Error — which includes ApiException, since it
  // `implements Exception`. Driving a NETWORK_ERROR retry through an actual
  // provider would mean waiting on real backoff timers outside a widget
  // test's fake clock (plain `test()` blocks get no such fast-forwarding),
  // so the retry-vs-no-retry decision is asserted directly against the
  // policy function instead. It delegates the actual backoff duration to
  // ProviderContainer.defaultRetry, so that part is exercised too, just
  // without waiting for it to elapse.
  group('apiRetryPolicy', () {
    test('does not retry a permanent, server-named error', () {
      const error = ApiException('EXERCISE_NOT_FOUND', 'No live exercise with id 1.');
      expect(apiRetryPolicy(0, error), isNull);
    });

    test('does not retry INVALID_QUERY_PARAM, INVALID_RESPONSE or UNKNOWN_ERROR', () {
      for (final code in ['INVALID_QUERY_PARAM', 'INVALID_RESPONSE', 'UNKNOWN_ERROR']) {
        expect(apiRetryPolicy(0, ApiException(code, 'x')), isNull, reason: code);
      }
    });

    test('retries NETWORK_ERROR, deferring the backoff to the framework default', () {
      const error = ApiException('NETWORK_ERROR', 'Could not reach the server.');
      expect(apiRetryPolicy(0, error), ProviderContainer.defaultRetry(0, error));
      expect(apiRetryPolicy(3, error), ProviderContainer.defaultRetry(3, error));
    });

    test('does not retry an error that is not an ApiException', () {
      expect(apiRetryPolicy(0, StateError('bug')), isNull);
    });
  });

  test('a permanent failure produces exactly one call, not ten retries', () async {
    final repo = _FailingRepository(
      const ApiException('EXERCISE_NOT_FOUND', 'No live exercise with id 1.'),
    );
    final container = ProviderContainer(overrides: [
      exerciseRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(exerciseDetailProvider(1).future),
      throwsA(isA<ApiException>()),
    );

    expect(repo.byIdCalls, 1);
  });
}
