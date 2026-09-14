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
  FakeRepository({
    this.failWith,
    this.pages = 1,
    this.failFiltersUntilCall = 0,
    this.emptyResults = false,
  });

  Object? failWith;
  final int pages;

  /// Answers every list call with no rows, so the empty state can be driven
  /// without a search term the fake would have to know is unmatchable.
  final bool emptyResults;

  /// Filter fetches below this call number fail, so a test can reproduce an
  /// outage that takes the filter bar down and then recovers.
  final int failFiltersUntilCall;

  int listCalls = 0;
  int filtersCalls = 0;
  String? lastMuscleGroup;
  String? lastSearch;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    listCalls++;
    lastMuscleGroup = muscleGroups.isEmpty ? null : muscleGroups.first;
    lastSearch = search;
    if (failWith != null) throw failWith!;
    if (emptyResults) {
      return ExercisePage(items: const [], page: page, limit: limit, total: 0);
    }
    return ExercisePage(
      items: [
        ExerciseSummary(
          exerciseId: page,
          name: search != null && search.isNotEmpty
              ? '$search $page'
              : muscleGroups.isEmpty
                  ? 'Sit-up $page'
                  : 'Curl $page',
          muscleGroup: muscleGroups.isEmpty ? 'abs' : muscleGroups.first,
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

/// Types [term] into the search box and waits out the debounce.
///
/// The wait is explicit because a pending [Timer] schedules no frame, so
/// pumpAndSettle alone can return before the debounce has fired -- a test that
/// relied on it would pass or fail on how long some unrelated animation
/// happened to keep the pump loop going.
Future<void> search(WidgetTester tester, String term) async {
  await tester.enterText(find.byKey(const Key('library.search')), term);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
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
  testWidgets('typing in the search box refetches with that term',
      (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(repo.lastSearch, isNull);

    await search(tester, 'plank');

    expect(repo.lastSearch, 'plank');
    expect(find.text('plank 1'), findsOneWidget);
  });

  testWidgets('a burst of keystrokes costs one request, not one each',
      (tester) async {
    // Every keystroke rebuilding the provider means a request per character
    // against a 1,200-row catalogue, and the answers can land out of order --
    // the list would settle on whichever response was slowest, not on what
    // the box says.
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();
    final before = repo.listCalls;

    final field = find.byKey(const Key('library.search'));
    for (final term in ['p', 'pl', 'pla', 'plan', 'plank']) {
      await tester.enterText(field, term);
      // Inside the debounce window, so each keystroke restarts it rather than
      // firing. Five 50ms gaps and a 300ms debounce is the point: elapsed
      // time alone would have fired it twice by now.
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(repo.listCalls - before, 1);
    expect(repo.lastSearch, 'plank');
  });

  testWidgets('clearing the search box goes back to the whole catalogue',
      (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await search(tester, 'plank');
    expect(repo.lastSearch, 'plank');

    await tester.tap(find.byKey(const Key('library.search.clear')));
    await tester.pumpAndSettle();

    expect(repo.lastSearch, isNull);
    expect(find.text('Sit-up 1'), findsOneWidget);
  });

  testWidgets('the search narrows the chosen muscle group rather than '
      'replacing it', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('biceps'));
    await tester.pumpAndSettle();
    await search(tester, 'curl');

    expect(repo.lastMuscleGroup, 'biceps',
        reason: 'the lit chip must still be applied');
    expect(repo.lastSearch, 'curl');
  });

  testWidgets('an empty result says so rather than looking broken',
      (tester) async {
    final repo = FakeRepository(emptyResults: true);
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await search(tester, 'zzzz');

    expect(find.textContaining('No exercises'), findsOneWidget);
  });

}
