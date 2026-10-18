import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/data/recent_exercises_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/domain/muscle_regions.dart';
import 'package:fitsync/features/exercises/presentation/exercise_detail_screen.dart';
import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/workout_draft.dart';

/// Records every list request, so a test can read back exactly what the
/// muscle buttons asked the server for.
class FakeExerciseRepository implements ExerciseRepository {
  FakeExerciseRepository({this.empty = false});

  /// Answers every list call with no rows, for the empty state.
  final bool empty;

  List<String>? lastMuscleGroups;
  String? lastEquipment;
  String? lastSearch;
  int listCalls = 0;

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
    lastMuscleGroups = muscleGroups;
    lastEquipment = equipment;
    lastSearch = search;
    return ExercisePage(
      items: empty
          ? const []
          : const [
              ExerciseSummary(
                exerciseId: 101,
                name: 'Goblet squat',
                muscleGroup: 'quads',
                equipment: 'dumbbell',
                thumbnailUrl: null,
              ),
              ExerciseSummary(
                exerciseId: 202,
                name: 'Cable fly',
                muscleGroup: 'pectorals',
                equipment: 'cable',
                thumbnailUrl: null,
              ),
            ],
      page: page,
      limit: limit,
      total: empty ? 0 : 2,
    );
  }

  @override
  Future<ExerciseFilters> filters() async => const ExerciseFilters(
    muscleGroups: [],
    equipment: [
      FilterOption(value: 'dumbbell', label: 'Dumbbells', count: 298),
    ],
  );

  /// Not found rather than a real row: the tests only need to know the
  /// detail screen was opened, and for which exercise.
  @override
  Future<ExerciseDetail> byId(int id) async =>
      throw const ApiException('EXERCISE_NOT_FOUND', 'No such exercise.');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// A catalogue long enough to scroll the Recent cards well out of view.
class _LongCatalogue extends FakeExerciseRepository {
  @override
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    String? search,
    int page = 1,
    int limit = 20,
  }) async => ExercisePage(
    items: [
      for (var i = 0; i < 40; i++)
        ExerciseSummary(
          exerciseId: 1000 + i,
          name: 'Catalogue exercise $i',
          muscleGroup: 'pectorals',
          equipment: 'dumbbell',
          thumbnailUrl: null,
        ),
    ],
    page: 1,
    limit: 40,
    total: 40,
  );
}

/// Answers the recent call with [items], [error], or never, as told.
class FakeRecentRepository implements RecentExercisesRepository {
  FakeRecentRepository({this.items = const [], this.error, this.hang = false});

  /// Not final, so a test can change the user's history between visits.
  List<ExerciseSummary> items;
  final Object? error;
  final bool hang;
  int calls = 0;

  @override
  Future<List<ExerciseSummary>> recent({int limit = 10}) {
    calls++;
    if (hang) return Completer<List<ExerciseSummary>>().future;
    if (error != null) return Future.error(error!);
    return Future.value(items);
  }
}

const _bench = ExerciseSummary(
  exerciseId: 7,
  name: 'Bench press',
  muscleGroup: 'pectorals',
  equipment: 'barbell',
  thumbnailUrl: null,
);

const _deadlift = ExerciseSummary(
  exerciseId: 8,
  name: 'Romanian deadlift',
  muscleGroup: 'hamstrings',
  equipment: 'barbell',
  thumbnailUrl: null,
  contraindicated: true,
);

ProviderContainer _container({
  FakeExerciseRepository? exercises,
  FakeRecentRepository? recent,
}) {
  final container = ProviderContainer(
    overrides: [
      exerciseRepositoryProvider.overrideWithValue(
        exercises ?? FakeExerciseRepository(),
      ),
      recentExercisesRepositoryProvider.overrideWithValue(
        recent ?? FakeRecentRepository(items: const [_bench, _deadlift]),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const ExerciseListScreen(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _region(String name) => find.byKey(Key('library.region.$name'));
Finder _recentStrip() => find.byKey(const Key('library.recent'));
Finder _recentCard(int id) => find.byKey(Key('recent.$id'));

Future<void> _tapRegion(WidgetTester tester, String name) async {
  await tester.ensureVisible(_region(name));
  await tester.pumpAndSettle();
  await tester.tap(_region(name));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String term) async {
  await tester.enterText(find.byKey(const Key('library.search')), term);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// Whether the button announces itself as the chosen one.
bool _isSelected(WidgetTester tester, Finder chip) {
  final node = tester.getSemantics(chip);
  return isSemantics(isSelected: true).matches(node, {});
}

void main() {
  group('muscle buttons', () {
    testWidgets('All and every body area are offered, All first and on', (
      tester,
    ) async {
      await _pump(tester, _container());

      expect(_region('all'), findsOneWidget);
      for (final region in MuscleRegion.values) {
        expect(find.text(region.label), findsOneWidget, reason: region.label);
      }
      expect(_isSelected(tester, _region('all')), isTrue);
      expect(_isSelected(tester, _region('chest')), isFalse);
    });

    testWidgets('each area asks for exactly its own muscle groups', (
      tester,
    ) async {
      final exercises = FakeExerciseRepository();
      await _pump(tester, _container(exercises: exercises));

      for (final region in MuscleRegion.values) {
        await _tapRegion(tester, region.name);
        expect(
          exercises.lastMuscleGroups,
          region.muscleGroups,
          reason: region.label,
        );
        expect(_isSelected(tester, _region(region.name)), isTrue);
      }
    });

    testWidgets('All asks for no muscle group', (tester) async {
      final exercises = FakeExerciseRepository();
      await _pump(tester, _container(exercises: exercises));

      await _tapRegion(tester, 'back');
      expect(exercises.lastMuscleGroups, MuscleRegion.back.muscleGroups);

      await _tapRegion(tester, 'all');
      expect(exercises.lastMuscleGroups, isEmpty);
      expect(_isSelected(tester, _region('all')), isTrue);
    });

    testWidgets('an area combines with the search and the equipment', (
      tester,
    ) async {
      final exercises = FakeExerciseRepository();
      await _pump(tester, _container(exercises: exercises));

      await tester.tap(find.byKey(const Key('library.equipment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('equipment.option.dumbbell')));
      await tester.pumpAndSettle();
      await _search(tester, 'press');
      await _tapRegion(tester, 'shoulders');

      expect(exercises.lastMuscleGroups, MuscleRegion.shoulders.muscleGroups);
      expect(exercises.lastEquipment, 'dumbbell');
      expect(exercises.lastSearch, 'press');
    });

    testWidgets('the chosen area carries over to the next opening', (
      tester,
    ) async {
      // One set of filters for the catalogue, however often it is opened.
      final exercises = FakeExerciseRepository();
      final container = _container(exercises: exercises);
      await _pump(tester, container);
      await _tapRegion(tester, 'arms');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fsLightTheme(),
            home: const Scaffold(body: Text('elsewhere')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _pump(tester, container);

      expect(_isSelected(tester, _region('arms')), isTrue);
      expect(exercises.lastMuscleGroups, MuscleRegion.arms.muscleGroups);
    });

    testWidgets('an empty result offers to clear the filters, area and all', (
      tester,
    ) async {
      final exercises = FakeExerciseRepository(empty: true);
      final container = _container(exercises: exercises);
      await _pump(tester, container);
      await _tapRegion(tester, 'core');

      expect(find.text('No exercises match those filters.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('library.clearFilters')));
      await tester.pumpAndSettle();

      expect(container.read(selectedFiltersProvider).region, isNull);
      expect(exercises.lastMuscleGroups, isEmpty);
      expect(_isSelected(tester, _region('all')), isTrue);
    });

    testWidgets('every button is a full-size tap target', (tester) async {
      await _pump(tester, _container());

      for (final name in ['all', ...MuscleRegion.values.map((r) => r.name)]) {
        await tester.ensureVisible(_region(name));
        await tester.pumpAndSettle();
        final size = tester.getSize(
          find.byKey(Key('library.region.$name.target')),
        );
        expect(size.height, greaterThanOrEqualTo(48), reason: name);
        expect(size.width, greaterThanOrEqualTo(48), reason: name);
      }
    });

    testWidgets('a last-in-line area chosen elsewhere shows on screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = _container();
      container
          .read(selectedFiltersProvider.notifier)
          .setRegion(MuscleRegion.cardio);
      await _pump(tester, container);

      final rect = tester.getRect(_region('cardio'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    });
  });

  // Reported on a phone: the row ended with Core flush against the right-hand
  // edge, so nothing said Cardio was there to swipe to. Every button shows
  // without scrolling, wrapping onto another line when it must.
  for (final (size, scale) in [
    (const Size(393, 852), 1.0),
    (const Size(320, 640), 2.0),
  ]) {
    testWidgets(
      'every muscle button is on screen at ${size.width.toInt()} dp and '
      '$scale× text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, _container());

        expect(tester.takeException(), isNull);
        for (final name in [
          'all',
          for (final region in MuscleRegion.values) region.name,
        ]) {
          final chip = tester.getRect(_region(name));
          expect(chip.left, greaterThanOrEqualTo(0), reason: name);
          expect(chip.right, lessThanOrEqualTo(size.width), reason: name);
        }
      },
    );
  }

  group('recent fits the screen', () {
    // Reported on a phone: the fourth card hung off the right-hand edge and a
    // swipe from it was the phone's own Back gesture. As the muscle buttons
    // did, the cards now fit the width: one row, the rest a tap away.
    List<ExerciseSummary> recentOf(int count) => [
      for (var i = 0; i < count; i++)
        ExerciseSummary(
          exerciseId: 100 + i,
          name: 'Recent exercise $i',
          muscleGroup: 'pectorals',
          equipment: 'dumbbell',
          thumbnailUrl: null,
        ),
    ];
    final five = recentOf(5);
    final more = find.byKey(const Key('library.recent.more'));

    Future<void> phone(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      double text = 1,
      FakeRecentRepository? recent,
      FakeExerciseRepository? exercises,
      ProviderContainer? container,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        container ??
            _container(
              recent: recent ?? FakeRecentRepository(items: five),
              exercises: exercises,
            ),
      );
    }

    void allOnScreen(WidgetTester tester, double width) {
      for (var id = 100; id < 105; id++) {
        final card = _recentCard(id);
        if (card.evaluate().isEmpty) continue;
        final rect = tester.getRect(card);
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$id');
        expect(rect.right, lessThanOrEqualTo(width), reason: '$id');
      }
      expect(
        find.descendant(
          of: _recentStrip(),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          ),
        ),
        findsNothing,
        reason: 'nothing to swipe sideways',
      );
    }

    testWidgets('a phone shows the latest three, none past the edge', (
      tester,
    ) async {
      await phone(tester);
      for (final id in [100, 101, 102]) {
        expect(_recentCard(id), findsOneWidget, reason: '$id');
      }
      expect(_recentCard(103), findsNothing);
      expect(_recentCard(104), findsNothing);
      // Latest first, left to right.
      expect(
        tester.getTopLeft(_recentCard(100)).dx,
        lessThan(tester.getTopLeft(_recentCard(101)).dx),
      );
      allOnScreen(tester, 390);
    });

    testWidgets('Show all opens the rest in rows, Show less folds them', (
      tester,
    ) async {
      await phone(tester);
      expect(
        find.descendant(of: more, matching: find.text('Show all 5')),
        findsOneWidget,
      );

      await tester.tap(more);
      await tester.pumpAndSettle();
      for (var id = 100; id < 105; id++) {
        expect(_recentCard(id), findsOneWidget, reason: '$id');
      }
      // A short last row keeps the columns of the rows above.
      expect(
        tester.getSize(_recentCard(103)).width,
        tester.getSize(_recentCard(100)).width,
      );
      // The fourth starts a second row under the first.
      expect(
        tester.getTopLeft(_recentCard(103)).dy,
        greaterThan(tester.getBottomLeft(_recentCard(100)).dy),
      );
      allOnScreen(tester, 390);
      expect(
        find.descendant(of: more, matching: find.text('Show less')),
        findsOneWidget,
      );

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(_recentCard(103), findsNothing);
    });

    testWidgets('no button when every recent one fits', (tester) async {
      await _pump(tester, _container());
      expect(_recentCard(7), findsOneWidget);
      expect(_recentCard(8), findsOneWidget);
      expect(more, findsNothing);
    });

    testWidgets('at large text fewer fit a row, still none past the edge', (
      tester,
    ) async {
      await phone(tester, size: const Size(320, 640), text: 2);
      expect(tester.takeException(), isNull);
      expect(_recentCard(100), findsOneWidget);
      // One a row: names this size need a card's whole width.
      expect(_recentCard(101), findsNothing);
      expect(_recentCard(102), findsNothing);
      expect(more, findsOneWidget);
      allOnScreen(tester, 320);
    });

    testWidgets('Show all stays open after scrolling away and back', (
      tester,
    ) async {
      await phone(
        tester,
        recent: FakeRecentRepository(items: recentOf(10)),
        exercises: _LongCatalogue(),
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(_recentCard(109), findsOneWidget);

      final list = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      await tester.drag(list.last, const Offset(0, -2500));
      await tester.pumpAndSettle();
      await tester.drag(list.last, const Offset(0, 2500));
      await tester.pumpAndSettle();

      expect(_recentCard(109), findsOneWidget);
      expect(
        find.descendant(of: more, matching: find.text('Show less')),
        findsOneWidget,
      );
    });

    testWidgets('a list that stops overflowing forgets it was opened', (
      tester,
    ) async {
      final recent = FakeRecentRepository(items: five);
      final container = _container(recent: recent);
      await phone(tester, container: container);
      await tester.tap(more);
      await tester.pumpAndSettle();

      recent.items = recentOf(2);
      container.invalidate(recentExercisesProvider);
      await tester.pumpAndSettle();
      expect(more, findsNothing);

      recent.items = five;
      container.invalidate(recentExercisesProvider);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: more, matching: find.text('Show all 5')),
        findsOneWidget,
      );
      expect(_recentCard(103), findsNothing);
    });

    testWidgets('the button says whether the list is open, in its own words', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await phone(tester);
      expect(
        tester.getSemantics(more),
        containsSemantics(hasExpandedState: true, isExpanded: false),
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(more),
        containsSemantics(hasExpandedState: true, isExpanded: true),
      );
      // What a voice user says, "Show less", is in what it is called.
      expect(find.bySemanticsLabel(RegExp('^Show less')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a common 360 dp Android shows the latest three', (
      tester,
    ) async {
      await phone(tester, size: const Size(360, 780));
      for (final id in [100, 101, 102]) {
        expect(_recentCard(id), findsOneWidget, reason: '$id');
      }
      allOnScreen(tester, 360);
    });

    testWidgets('a wide screen keeps the cards their size', (tester) async {
      await phone(tester, size: const Size(844, 600));
      expect(tester.getSize(_recentCard(100)).width, lessThanOrEqualTo(176));
    });

    testWidgets('the title is never cut at the largest text', (tester) async {
      await phone(tester, size: const Size(600, 900), text: 4);
      final title = tester.renderObject<RenderParagraph>(find.text('Recent'));
      expect(
        title.size.height,
        greaterThanOrEqualTo(
          title.getMaxIntrinsicHeight(double.infinity) - 0.5,
        ),
      );
    });

    testWidgets('the button is a full-size target, and says what it shows', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await phone(tester);
      final size = tester.getSize(more);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(
        find.bySemanticsLabel('Show all 5 recent exercises'),
        findsOneWidget,
      );
      // At the far right, on the title's line, where a "see all" is looked for.
      expect(tester.getTopRight(more).dx, closeTo(390 - 4, 1));
      expect(
        tester.getCenter(more).dy,
        closeTo(tester.getCenter(find.text('Recent')).dy, 4),
      );
      semantics.dispose();
    });
  });

  group('recent strip', () {
    testWidgets('shows the recent exercises when nothing is filtered', (
      tester,
    ) async {
      await _pump(tester, _container());

      expect(_recentStrip(), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(_recentCard(7), findsOneWidget);
      expect(_recentCard(8), findsOneWidget);
      expect(
        find.descendant(
          of: _recentCard(8),
          matching: find.byIcon(Icons.shield_outlined),
        ),
        findsOneWidget,
        reason: 'the injury mark travels with the exercise',
      );
    });

    testWidgets('its cards are one height, short name or long', (tester) async {
      // A one-line name beside a two-line one left the strip ragged, unlike
      // the prototype's even cards.
      const short = ExerciseSummary(
        exerciseId: 9,
        name: 'Plank',
        muscleGroup: 'abs',
        equipment: 'body weight',
        thumbnailUrl: null,
      );
      const long = ExerciseSummary(
        exerciseId: 10,
        name: 'Dumbbell single-arm bent-over row',
        muscleGroup: 'upper back',
        equipment: 'dumbbell',
        thumbnailUrl: null,
      );
      await _pump(
        tester,
        _container(recent: FakeRecentRepository(items: const [short, long])),
      );

      expect(
        tester.getSize(_recentCard(9)).height,
        tester.getSize(_recentCard(10)).height,
      );
    });

    testWidgets('an area hides it', (tester) async {
      await _pump(tester, _container());
      await _tapRegion(tester, 'chest');
      expect(_recentStrip(), findsNothing);
    });

    testWidgets('a search term hides it', (tester) async {
      await _pump(tester, _container());
      await _search(tester, 'row');
      expect(_recentStrip(), findsNothing);
    });

    testWidgets('equipment hides it', (tester) async {
      await _pump(tester, _container());
      await tester.tap(find.byKey(const Key('library.equipment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('equipment.option.dumbbell')));
      await tester.pumpAndSettle();
      expect(_recentStrip(), findsNothing);
    });

    testWidgets('a failed fetch hides it and leaves the list alone', (
      tester,
    ) async {
      await _pump(
        tester,
        _container(
          recent: FakeRecentRepository(
            error: const ApiException('INTERNAL', 'Boom.'),
          ),
        ),
      );

      expect(_recentStrip(), findsNothing);
      expect(find.text('Boom.'), findsNothing);
      expect(find.text('Goblet squat'), findsOneWidget);
    });

    testWidgets('no history hides it', (tester) async {
      await _pump(tester, _container(recent: FakeRecentRepository()));
      expect(_recentStrip(), findsNothing);
      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('it stays hidden while loading, with no spinner of its own', (
      tester,
    ) async {
      await _pump(
        tester,
        _container(recent: FakeRecentRepository(hang: true)),
        settle: false,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Goblet squat'), findsOneWidget);
      expect(_recentStrip(), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('picking: a card toggles it into the workout', (tester) async {
      final container = _container();
      await _pump(tester, container);

      await tester.tap(_recentCard(7));
      await tester.pumpAndSettle();

      expect(container.read(workoutDraftProvider).exerciseIds, [7]);
      expect(find.text('1 added'), findsOneWidget);
      expect(
        tester.getSemantics(_recentCard(7)).label,
        'Bench press, recent, added',
      );

      await tester.tap(_recentCard(7));
      await tester.pumpAndSettle();

      expect(container.read(workoutDraftProvider), isEmpty);
      expect(find.text('0 added'), findsOneWidget);
      expect(
        tester.getSemantics(_recentCard(7)).label,
        'Bench press, recent, not added',
      );
    });

    testWidgets(
      'picking: a row picked in the list shows as added on its card',
      (tester) async {
        final container = _container();
        container.read(workoutDraftProvider.notifier).toggle(_bench);
        await _pump(tester, container);

        expect(
          find.descendant(
            of: _recentCard(7),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('picking: a screen reader can toggle a card', (tester) async {
      final handle = tester.ensureSemantics();
      final container = _container();
      await _pump(tester, container);

      final node = tester.getSemantics(_recentCard(7));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(
        find.semantics.byLabel('Bench press, recent, not added'),
      );
      await tester.pumpAndSettle();

      expect(container.read(workoutDraftProvider).exerciseIds, [7]);
      handle.dispose();
    });

    testWidgets('each opening asks once, and sees what was logged since', (
      tester,
    ) async {
      final recent = FakeRecentRepository(items: const [_bench]);
      final container = _container(recent: recent);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigator,
            theme: fsLightTheme(),
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      Future<void> open() async {
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const ExerciseListScreen()),
        );
        await tester.pumpAndSettle();
      }

      await open();
      // One request, not a second one straight after it.
      expect(recent.calls, 1);
      expect(_recentCard(8), findsNothing);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      // A workout logged since: the deadlift is now the latest.
      recent.items = const [_deadlift, _bench];
      await open();

      expect(recent.calls, 2);
      expect(_recentCard(8), findsOneWidget);
    });

    testWidgets('large text gives fewer, wider cards', (tester) async {
      final container = _container();
      Future<void> at(double text) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: fsLightTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(320, 640),
                  textScaler: TextScaler.linear(text),
                ),
                child: const ExerciseListScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await at(1);
      final normal = tester.getSize(_recentCard(7)).width;
      expect(_recentCard(8), findsOneWidget, reason: 'two side by side');

      await at(2);
      expect(_recentCard(8), findsNothing, reason: 'one a row');
      expect(tester.getSize(_recentCard(7)).width, greaterThan(normal));
    });

    testWidgets('every card is a full-size tap target', (tester) async {
      await _pump(tester, _container());
      for (final id in [7, 8]) {
        final size = tester.getSize(_recentCard(id));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
    });
  });

  group('the info button', () {
    testWidgets('picking: it opens the demo without picking the row', (
      tester,
    ) async {
      final container = _container();
      await _pump(tester, container);

      final info = find.byKey(const Key('tile.info.202'));
      expect(info, findsOneWidget);
      expect(find.byTooltip('About Cable fly'), findsOneWidget);
      expect(tester.getSize(info).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(info).width, greaterThanOrEqualTo(48));

      await tester.tap(info);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ExerciseDetailScreen>(find.byType(ExerciseDetailScreen))
            .exerciseId,
        202,
      );
      expect(container.read(workoutDraftProvider), isEmpty);
    });

    testWidgets('picking: the row itself still toggles the pick', (
      tester,
    ) async {
      final container = _container();
      await _pump(tester, container);

      await tester.tap(find.text('Cable fly'));
      await tester.pumpAndSettle();

      expect(container.read(workoutDraftProvider).exerciseIds, [202]);
      expect(find.byType(ExerciseDetailScreen), findsNothing);
    });
  });

  testWidgets('320 dp at 2x text does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: fsLightTheme(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: ExerciseListScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_recentStrip(), findsOneWidget);

    // Picking something too, so the added state is laid out as well.
    await tester.tap(_recentCard(7));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _tapRegion(tester, 'cardio');
    expect(tester.takeException(), isNull);
  });
}
