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
  String? lastEquipment;
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
    lastEquipment = equipment;
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
              : equipment != null
                  ? '$equipment press $page'
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
      equipment: [
        FilterOption(value: 'barbell', label: 'Barbell', count: 214),
        FilterOption(value: 'body weight', label: 'Bodyweight', count: 304),
        FilterOption(value: 'dumbbell', label: 'Dumbbells', count: 298),
        FilterOption(value: 'machines', label: 'Machines', count: 41),
      ],
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

  testWidgets('the catalogue is narrowed by equipment, not by a chip strip',
      (tester) async {
    // The strip put every muscle group ahead of the equipment tags in one
    // sideways scroller, so reaching "dumbbell" meant scrolling past all of
    // them. Equipment now has its own labelled control and the strip is gone.
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library.equipment')), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing,
        reason: 'the chip strip is gone');
    expect(find.text('biceps'), findsNothing,
        reason: 'muscle groups are no longer a filter control');
  });

  testWidgets('choosing equipment refetches the list with it', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(repo.lastEquipment, isNull);

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('equipment.option.dumbbell')));
    await tester.pumpAndSettle();

    expect(repo.lastEquipment, 'dumbbell');
    expect(find.text('dumbbell press 1'), findsOneWidget);
  });

  testWidgets('the button names the equipment in force', (tester) async {
    // The whole point of moving it out of the strip: what is filtering the
    // list is readable without opening anything.
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Equipment'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('equipment.option.barbell')));
    await tester.pumpAndSettle();

    expect(find.text('Barbell'), findsOneWidget);
    expect(find.text('Equipment'), findsNothing);
  });

  testWidgets('the sheet names gear the way onboarding does', (tester) async {
    // The catalogue tags gear as 'smith machine', 'ez barbell', 'cable'. The
    // user picked 'Machines' and 'Barbell' during onboarding and has never
    // been shown the dataset's vocabulary -- so the filter must not be the
    // first place they meet it.
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();

    expect(find.text('Machines'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);
    expect(find.text('body weight'), findsNothing,
        reason: 'the raw catalogue tag is a key, not a label');
  });

  testWidgets('the key sent to the server is the value, not the label',
      (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bodyweight'));
    await tester.pumpAndSettle();

    expect(repo.lastEquipment, 'body weight',
        reason: 'the label is for the user; the value is the API contract');
  });

  testWidgets('the sheet says how many exercises each tag has', (tester) async {
    // A tag with 41 rows behind it and one with 304 are different choices,
    // and the count is what tells them apart before committing to the fetch.
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();

    expect(find.text('304'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
  });

  testWidgets('typing in the sheet narrows the tags', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('equipment.option.barbell')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('equipment.search')), 'mach');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('equipment.option.machines')), findsOneWidget);
    expect(find.byKey(const Key('equipment.option.barbell')), findsNothing);
  });

  testWidgets('any equipment takes the filter back off', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('equipment.option.dumbbell')));
    await tester.pumpAndSettle();
    expect(repo.lastEquipment, 'dumbbell');

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('equipment.option.any')));
    await tester.pumpAndSettle();

    expect(repo.lastEquipment, isNull);
    expect(find.text('Equipment'), findsOneWidget);
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
    expect(find.byKey(const Key('library.equipment')), findsNothing,
        reason: 'filters failed too');

    repo.failWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Sit-up 1'), findsOneWidget, reason: 'list recovered');
    expect(find.byKey(const Key('library.equipment')), findsOneWidget,
        reason: 'the equipment filter must recover too');
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

  testWidgets('the search narrows the chosen equipment rather than '
      'replacing it', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library.equipment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('equipment.option.dumbbell')));
    await tester.pumpAndSettle();
    await search(tester, 'curl');

    expect(repo.lastEquipment, 'dumbbell',
        reason: 'the chosen equipment must still be applied');
    expect(repo.lastSearch, 'curl');
  });

  testWidgets('a re-opened library shows the term it is still filtering by',
      (tester) async {
    // The box is part of the screen; the term outlives it. Backing out of the
    // library and going back in gave a fresh, empty box above a list still
    // filtered to the old term -- and the clear button only appears when the
    // box has text, so there was nothing on screen to explain the short list
    // or undo it.
    final repo = FakeRepository();
    final container = ProviderContainer(
      overrides: [exerciseRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ExerciseListScreen()),
    ));
    await tester.pumpAndSettle();
    await search(tester, 'bench');
    expect(repo.lastSearch, 'bench');

    // Leave the library, then come back to a freshly built one.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ExerciseListScreen()),
    ));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(const Key('library.search'))).controller!.text,
      'bench',
      reason: 'the box must show the term the list is obeying',
    );
    expect(find.byKey(const Key('library.search.clear')), findsOneWidget,
        reason: 'and it must be clearable');
  });

  testWidgets('clearing a restored term goes back to the whole catalogue',
      (tester) async {
    final repo = FakeRepository();
    final container = ProviderContainer(
      overrides: [exerciseRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ExerciseListScreen()),
    ));
    await tester.pumpAndSettle();
    await search(tester, 'bench');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ExerciseListScreen(selecting: true)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library.search.clear')));
    await tester.pumpAndSettle();

    expect(repo.lastSearch, isNull);
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
