import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not part of the main flutter_riverpod.dart barrel export in
// 3.4.2 — it moved under misc.dart. Needed here only for the harness
// helper's parameter type below.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/exercise_detail_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/workout_draft.dart';

const _detail = ExerciseDetail(
  exerciseId: 1,
  name: '3/4 sit-up',
  muscleGroup: 'abs',
  equipment: 'body weight',
  thumbnailUrl: '/storage/exercises/0001/thumb.jpg',
  animationUrl: '/storage/exercises/0001/animation.gif',
  cues: ['Lie flat on your back.', 'Curl forward.'],
);

Widget harness(Override override) => ProviderScope(
  overrides: [override],
  child: const MaterialApp(home: ExerciseDetailScreen(exerciseId: 1)),
);

// The default flutter_test surface is 800x600 logical px — wider than it is
// tall, unlike any phone this app targets. The detail screen's hero image is
// AspectRatio(1) at the ListView's ~768px width, so on the default surface
// alone it is already ~768px tall: taller than the whole viewport. That
// pushes the chips and cues below the SliverList's lazy-build window, so
// they are never mounted and `find` cannot see them — not a rendering bug,
// just an unrepresentative test surface. A portrait phone-sized surface
// gives the square image a sane height and matches real usage.
void _usePortraitSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// SE-7: built through fromJson, as the repository builds it, so these tests
// pin what the app reads off GET /exercises/:id rather than a constructor.
ExerciseDetail _detailFromServer({required bool contraindicated}) =>
    ExerciseDetail.fromJson({
      'exerciseId': 1,
      'name': '3/4 sit-up',
      'muscleGroup': 'abs',
      'equipment': 'body weight',
      'thumbnailUrl': null,
      'contraindicated': contraindicated,
      'animationUrl': null,
      'cues': ['Lie flat on your back.'],
    });

const _summary = ExerciseSummary(
  exerciseId: 1,
  name: '3/4 sit-up',
  muscleGroup: 'abs',
  equipment: 'body weight',
  thumbnailUrl: null,
);

void main() {
  // Opened from the picker's ⓘ, the demo is where the choice gets made; it
  // must be able to act on it rather than send the user back to find the row.
  group('opened from the picker', () {
    Future<ProviderContainer> pumpPicker(
      WidgetTester tester, {
      ExerciseSummary pick = _summary,
    }) async {
      _usePortraitSurface(tester);
      final container = ProviderContainer(
        overrides: [
          exerciseDetailProvider(1).overrideWith((ref) async => _detail),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ExerciseDetailScreen(exerciseId: 1, pick: pick),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('adds the exercise to the workout, and takes it back out', (
      tester,
    ) async {
      final container = await pumpPicker(tester);

      await tester.tap(find.text('Add to workout'));
      await tester.pumpAndSettle();
      expect(container.read(workoutDraftProvider).holds(1), isTrue);

      expect(find.text('Remove from workout'), findsOneWidget);
      await tester.tap(find.text('Remove from workout'));
      await tester.pumpAndSettle();
      expect(container.read(workoutDraftProvider).holds(1), isFalse);
    });

    // SE-22: this was the one place in the app that added an exercise with
    // no word that it loads a reported injury.
    testWidgets('warns above the button when it loads a reported injury', (
      tester,
    ) async {
      await pumpPicker(
        tester,
        pick: const ExerciseSummary(
          exerciseId: 1,
          name: '3/4 sit-up',
          muscleGroup: 'abs',
          equipment: 'body weight',
          thumbnailUrl: null,
          contraindicated: true,
        ),
      );

      expect(find.text('Loads an injury you reported'), findsOneWidget);
      final shield = tester.widget<Icon>(find.byKey(const Key('detail.risk')));
      expect(shield.icon, Icons.shield_outlined);
      expect(shield.color, tester.element(find.byType(Scaffold)).fs.red);
      expect(
        tester.getBottomLeft(find.text('Loads an injury you reported')).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('detail.pick'))).dy,
        ),
      );
    });

    testWidgets('says nothing of injuries when it loads none', (tester) async {
      await pumpPicker(tester);

      expect(find.text('Loads an injury you reported'), findsNothing);
      expect(find.byKey(const Key('detail.risk')), findsNothing);
    });

    // SE-7: the row may be older than the user's latest injury report; the
    // detail the server sends now still warns, and still only once.
    testWidgets('a picked row the server now flags still warns', (
      tester,
    ) async {
      _usePortraitSurface(tester);
      final container = ProviderContainer(
        overrides: [
          exerciseDetailProvider(1).overrideWith(
            (ref) async => _detailFromServer(contraindicated: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ExerciseDetailScreen(exerciseId: 1, pick: _summary),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detail.risk')), findsOneWidget);
      expect(find.text('Loads an injury you reported'), findsOneWidget);
      // In the bottom bar, below the name, right above the button.
      final line = tester.getBottomLeft(
        find.text('Loads an injury you reported'),
      );
      expect(
        line.dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('detail.pick'))).dy,
        ),
      );
      expect(
        line.dy,
        greaterThan(tester.getBottomLeft(find.text('3/4 sit-up')).dy),
      );
    });
  });

  // SE-7: the Plan tab opens the demo with no picker row, so the warning
  // comes from the detail itself and sits above the name.
  group('opened from the plan', () {
    Future<void> pumpPlan(
      WidgetTester tester, {
      required bool contraindicated,
    }) async {
      await tester.pumpWidget(
        harness(
          exerciseDetailProvider(1).overrideWith(
            (ref) async => _detailFromServer(contraindicated: contraindicated),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('it warns when the exercise loads a reported injury', (
      tester,
    ) async {
      _usePortraitSurface(tester);
      await pumpPlan(tester, contraindicated: true);

      expect(find.byKey(const Key('detail.risk')), findsOneWidget);
      expect(find.text('Loads an injury you reported'), findsOneWidget);
      expect(find.byKey(const Key('detail.pick')), findsNothing);
      final shield = tester.widget<Icon>(find.byKey(const Key('detail.risk')));
      expect(shield.icon, Icons.shield_outlined);
      expect(shield.size, 14);
      expect(shield.color, tester.element(find.byType(Scaffold)).fs.red);
      expect(
        tester.getBottomLeft(find.text('Loads an injury you reported')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('3/4 sit-up')).dy),
      );
    });

    testWidgets('it says nothing of injuries it does not load', (tester) async {
      _usePortraitSurface(tester);
      await pumpPlan(tester, contraindicated: false);

      expect(find.byKey(const Key('detail.risk')), findsNothing);
      expect(find.text('Loads an injury you reported'), findsNothing);
    });

    testWidgets('at 2x text on a 360 dp phone the warning wraps, uncut', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPlan(tester, contraindicated: true);

      expect(tester.takeException(), isNull);
      final words = find.text('Loads an injury you reported');
      expect(words, findsOneWidget);
      final text = tester.widget<Text>(words);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      // 12.5 at 2x is 25 logical px a line; more than one line means it
      // wrapped rather than ran off the edge.
      expect(tester.getSize(words).height, greaterThan(30));
      expect(tester.getTopRight(words).dx, lessThanOrEqualTo(360));
    });
  });

  testWidgets('opened from anywhere else, it offers no workout button', (
    tester,
  ) async {
    _usePortraitSurface(tester);
    await tester.pumpWidget(
      harness(exerciseDetailProvider(1).overrideWith((ref) async => _detail)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to workout'), findsNothing);
  });

  testWidgets('renders the name, metadata and numbered cues', (tester) async {
    _usePortraitSurface(tester);
    await tester.pumpWidget(
      harness(exerciseDetailProvider(1).overrideWith((ref) async => _detail)),
    );
    await tester.pumpAndSettle();

    expect(find.text('3/4 sit-up'), findsOneWidget);
    expect(find.textContaining('Abs'), findsWidgets);
    // The cue list moved into AiCueList, shared with the workout's demo stage,
    // so the number is its own widget rather than a "1. " prefix on the text.
    expect(find.text('How to perform'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Lie flat on your back.'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Curl forward.'), findsOneWidget);
  });

  testWidgets('surfaces the server error message with a retry', (tester) async {
    _usePortraitSurface(tester);
    // A counter, not just a non-throwing tap: proves the button causes a
    // second fetch rather than merely existing and being tappable. Also
    // incidentally confirms the initial failure (a permanent, server-named
    // error) is not silently retried by Riverpod's own default retry policy
    // before the tap — see apiRetryPolicy in providers.dart.
    var calls = 0;
    await tester.pumpWidget(
      harness(
        exerciseDetailProvider(1).overrideWith((ref) async {
          calls++;
          throw const ApiException(
            'EXERCISE_NOT_FOUND',
            'No live exercise with id 1.',
          );
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No live exercise with id 1.'), findsOneWidget);
    expect(find.byType(FsRetry), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(calls, 2);
  });

  testWidgets('a broken reply is reported in plain words', (tester) async {
    _usePortraitSurface(tester);
    await tester.pumpWidget(
      harness(
        exerciseDetailProvider(1).overrideWith((ref) async {
          throw const ApiException(
            'INVALID_RESPONSE',
            'Server returned a non-JSON body (HTTP 502).',
          );
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong on our side. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('HTTP'), findsNothing);
    expect(find.textContaining('adb'), findsNothing);
  });

  testWidgets('an unreachable animation does not crash the screen', (
    tester,
  ) async {
    _usePortraitSurface(tester);
    await tester.pumpWidget(
      harness(exerciseDetailProvider(1).overrideWith((ref) async => _detail)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('3/4 sit-up'), findsOneWidget);
  });

  // SE-7: GET /exercises/:id now says whether the exercise loads a reported
  // injury; a reply from before the field existed reads as nothing known.
  group('ExerciseDetail.fromJson', () {
    test('reads contraindicated', () {
      expect(_detailFromServer(contraindicated: true).contraindicated, isTrue);
      expect(
        _detailFromServer(contraindicated: false).contraindicated,
        isFalse,
      );
    });

    test('an absent contraindicated reads as false', () {
      final detail = ExerciseDetail.fromJson({
        'exerciseId': 1,
        'name': '3/4 sit-up',
        'muscleGroup': 'abs',
        'equipment': null,
        'thumbnailUrl': null,
        'animationUrl': null,
        'cues': <String>[],
      });
      expect(detail.contraindicated, isFalse);
    });
  });
}
