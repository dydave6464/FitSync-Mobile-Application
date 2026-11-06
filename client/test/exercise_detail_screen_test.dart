import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not part of the main flutter_riverpod.dart barrel export in
// 3.4.2 — it moved under misc.dart. Needed here only for the harness
// helper's parameter type below.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
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
    Future<ProviderContainer> pumpPicker(WidgetTester tester) async {
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
          child: const MaterialApp(
            home: ExerciseDetailScreen(exerciseId: 1, pick: _summary),
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
}
