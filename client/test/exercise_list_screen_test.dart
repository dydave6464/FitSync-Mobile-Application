import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';

class FakeRepository implements ExerciseRepository {
  FakeRepository({this.failWith, this.pages = 1, this.failFiltersUntilCall = 0});

  Object? failWith;
  final int pages;

  /// Filter fetches below this call number fail, so a test can reproduce an
  /// outage that takes the filter bar down and then recovers.
  final int failFiltersUntilCall;

  int listCalls = 0;
  int filtersCalls = 0;
  String? lastMuscleGroup;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExercisePage> list({
    String? muscleGroup,
    String? equipment,
    int page = 1,
    int limit = 20,
  }) async {
    listCalls++;
    lastMuscleGroup = muscleGroup;
    if (failWith != null) throw failWith!;
    return ExercisePage(
      items: [
        ExerciseSummary(
          exerciseId: page,
          name: muscleGroup == null ? 'Sit-up $page' : 'Curl $page',
          muscleGroup: muscleGroup ?? 'abs',
          equipment: 'body weight',
          thumbnailUrl: '/storage/exercises/000$page/thumb.jpg',
        ),
      ],
      page: page,
      limit: limit,
      total: pages,
    );
  }

  @override
  Future<ExerciseDetail> byId(int id) async => throw UnimplementedError();

  @override
  Future<ExerciseFilters> filters() async {
    filtersCalls++;
    if (filtersCalls <= failFiltersUntilCall) {
      throw const ApiException('NETWORK_ERROR', 'Could not reach the server.');
    }
    return const ExerciseFilters(
        muscleGroups: [FilterOption(value: 'abs', count: 147), FilterOption(value: 'biceps', count: 150)],
      equipment: [FilterOption(value: 'body weight', count: 304)],
    );
  }
}

Widget harness(FakeRepository repo) => ProviderScope(
      overrides: [exerciseRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ExerciseListScreen()),
    );

void main() {
  testWidgets('shows a loading indicator, then the exercises', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Sit-up 1'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the server error code and retries on demand', (tester) async {
    // NETWORK_ERROR is deliberately avoided here: it is the one code
    // apiRetryPolicy treats as transient, so it would retry automatically
    // (up to Riverpod's default 10 attempts) instead of surfacing on the
    // first failure the way this test expects. INVALID_QUERY_PARAM is
    // permanent from the client's side and surfaces immediately, matching
    // the equivalent case in exercise_detail_screen_test.dart.
    final repo = FakeRepository(failWith: const ApiException('INVALID_QUERY_PARAM', 'Unsupported filter value.'));
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unsupported filter value.'), findsOneWidget);
    expect(repo.listCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repo.listCalls, 2, reason: 'retry must actually refetch');
  });

  testWidgets('selecting a muscle group refetches with that filter', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(repo.lastMuscleGroup, isNull);

    await tester.tap(find.text('biceps'));
    await tester.pumpAndSettle();

    expect(repo.lastMuscleGroup, 'biceps');
    expect(find.text('Curl 1'), findsOneWidget);
  });

  testWidgets('retry brings the filter bar back, not just the list', (tester) async {
    // An outage takes down both providers. Retry must recover both — a filter
    // bar that stays dead until app restart looks fixed but is not.
    final repo = FakeRepository(
      failWith: const ApiException('NETWORK_ERROR', 'Could not reach the server.'),
      // Fail every attempt the retry policy allows (1 initial + 2 retries), so
      // the provider settles into a real error state the way a genuine outage
      // leaves it — rather than self-healing on the fake clock.
      failFiltersUntilCall: 3,
    );
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('biceps'), findsNothing, reason: 'filters failed too');

    repo.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Sit-up 1'), findsOneWidget, reason: 'list recovered');
    expect(find.text('biceps'), findsOneWidget, reason: 'filter bar must recover too');
  });

  testWidgets('a missing thumbnail does not break the row', (tester) async {
    // Flutter's test harness fails every image request, so this exercises the
    // errorBuilder path on every run.
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sit-up 1'), findsOneWidget);
  });
}
