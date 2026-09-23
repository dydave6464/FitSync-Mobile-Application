import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart'
    show apiClientProvider;
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/plans/presentation/start_workout_sheet.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show injuryOptionsProvider;
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/session_outcome.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/outcome_sheet.dart'
    show outcomeNotSavedMessage;
import 'package:fitsync/features/sessions/presentation/workout_draft.dart';
import 'package:fitsync/features/sessions/presentation/workout_review_screen.dart';
import 'package:fitsync/features/sessions/presentation/workout_setup_screen.dart';

/// The real face, not the test harness's. The default test font renders
/// FsTag('Recommended') at 136dp against Space Grotesk's ~62dp, which is
/// enough to invert a conclusion about whether this sheet fits.
Future<void> _loadFont() async {
  final bytes = await File('assets/fonts/SpaceGrotesk-Variable.ttf')
      .readAsBytes();
  await (FontLoader(
    'SpaceGrotesk',
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// A workout already trained, as GET /sessions/last reports it.
const _lastWorkout = LastWorkout(
  sessionId: 32,
  sessionDate: '2026-09-14',
  planName: null,
  exercises: [
    ExerciseSummary(
      exerciseId: 101,
      name: 'Goblet squat',
      muscleGroup: 'quadriceps',
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
);

Future<ProviderContainer> _open(
  WidgetTester tester, {
  WorkoutPlan? plan,
  TextScaler textScaler = TextScaler.noScaling,
  LastWorkout? last,
  Object? lastError,
  PendingOutcome? pending,
  Object? pendingError,
  Future<PendingOutcome?>? pendingFuture,
  // Serves the outcome POST for the chain tests that answer for real. The
  // other tests never submit an answer, so they never need one.
  http.Client? client,
}) async {
  final container = ProviderContainer(
    overrides: [
      activePlanProvider.overrideWith((ref) async => plan),
      lastWorkoutProvider.overrideWith((ref) async {
        if (lastError != null) throw lastError;
        return last;
      }),
      // Every test passes through the pending lookup now. Overridden so that
      // none of them reaches a real socket, which under the test binding
      // would never answer.
      pendingOutcomeProvider.overrideWith((ref) async {
        if (pendingFuture != null) return pendingFuture;
        if (pendingError != null) throw pendingError;
        return pending;
      }),
      injuryOptionsProvider.overrideWith((ref) async => const []),
      if (client != null)
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'http://test.local',
            tokens: TokenStore(backing: InMemorySecureStore()),
            client: client,
          ),
        ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: fsLightTheme(),
        // Above the Navigator on purpose: the sheet is a route, so a
        // MediaQuery under `home` would not reach it.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showStartWorkoutSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(_loadFont);

  /// Both rows visible and hit-testable, which is what a clipped sheet
  /// costs: `showModalBottomSheet` caps its child at 9/16 of the screen and
  /// a bare Column has nowhere to put the remainder, so the second row goes
  /// off the bottom edge -- a debug stripe, and in release nothing at all.
  void expectBothRowsUsable(WidgetTester tester) {
    expect(
      find.byKey(const Key('start.generator')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const Key('start.manual')).hitTestable(), findsOneWidget);
  }

  testWidgets('offers to repeat the last workout', (tester) async {
    // The row your mockup draws under "or pick up where you left off". Your
    // last workout is the template you come back to, which is what makes
    // manual logging feel like a first-class path rather than a detour.
    await _open(tester, last: _lastWorkout);

    expect(find.byKey(const Key('start.repeat')), findsOneWidget);
    expect(find.text('Repeat last workout'), findsOneWidget);
    expect(find.textContaining('Your own workout'), findsOneWidget);
    expect(find.textContaining('2 exercises'), findsOneWidget);
  });

  testWidgets('a repeated plan workout is named after its plan', (
    tester,
  ) async {
    await _open(
      tester,
      last: const LastWorkout(
        sessionId: 30,
        sessionDate: '2026-09-12',
        planName: 'Upper Body · Push',
        exercises: [
          ExerciseSummary(
            exerciseId: 1,
            name: 'Bench press',
            muscleGroup: 'chest',
            equipment: 'barbell',
            thumbnailUrl: null,
          ),
        ],
      ),
    );

    expect(find.textContaining('Upper Body · Push'), findsOneWidget);
    expect(find.textContaining('1 exercise'), findsOneWidget);
    expect(find.textContaining('1 exercises'), findsNothing);
  });

  testWidgets('nothing trained yet offers nothing to repeat', (tester) async {
    await _open(tester, last: null);

    expect(find.byKey(const Key('start.repeat')), findsNothing);
    expect(
      find.textContaining('pick up where you left off'),
      findsNothing,
      reason: 'a divider with nothing under it is furniture for nothing',
    );
  });

  testWidgets('a failed lookup simply omits the row', (tester) async {
    // The sheet's job is starting a workout. Losing the repeat shortcut must
    // not cost the two rows that do not depend on it.
    await _open(tester, lastError: Exception('offline'));

    expect(find.byKey(const Key('start.repeat')), findsNothing);
    expectBothRowsUsable(tester);
  });

  testWidgets('repeating loads the workout and opens review', (tester) async {
    // Review rather than straight into the logger: a repeat is rarely
    // identical, and the review screen already owns starting -- including the
    // guard for a workout that is already open.
    final container = await _open(tester, last: _lastWorkout);

    await tester.tap(find.byKey(const Key('start.repeat')));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutReviewScreen), findsOneWidget);
    expect(container.read(workoutDraftProvider).exerciseIds, [
      101,
      202,
    ], reason: 'in the order they were trained');
  });

  testWidgets('repeating replaces whatever was half-picked', (tester) async {
    // Appending would silently merge an abandoned selection into a workout
    // the user asked to repeat exactly.
    final container = await _open(tester, last: _lastWorkout);
    container
        .read(workoutDraftProvider.notifier)
        .toggle(
          const ExerciseSummary(
            exerciseId: 999,
            name: 'Leftover',
            muscleGroup: 'abs',
            equipment: null,
            thumbnailUrl: null,
          ),
        );

    await tester.tap(find.byKey(const Key('start.repeat')));
    await tester.pumpAndSettle();

    expect(container.read(workoutDraftProvider).exerciseIds, [101, 202]);
  });

  testWidgets('both rows survive a landscape viewport', (tester) async {
    // 844x390: an iPhone 14 turned sideways. Every other test in this file
    // runs at the harness's 800x600, where 9/16 leaves room to spare.
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);

    expectBothRowsUsable(tester);
  });

  testWidgets('both rows survive a small landscape viewport', (tester) async {
    // 640x360: the smallest Android phone the app targets, sideways.
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);

    expectBothRowsUsable(tester);
  });

  testWidgets('the largest text scale scrolls rather than clipping', (
    tester,
  ) async {
    // 2.0x on a 390x844 phone -- Android's largest font setting. At this
    // scale the two rows are taller than the whole screen, so no cap and no
    // amount of full-height sheet can show both at once: the remainder has
    // to be reachable rather than cut off. (1.5x fits with the real face
    // loaded; it only overflows under the test harness's much wider default
    // font, which is why this file loads Space Grotesk.)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester, textScaler: const TextScaler.linear(2));

    expect(
      find.byKey(const Key('start.generator')).hitTestable(),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const Key('start.generator')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('start.manual')).hitTestable(),
      findsOneWidget,
      reason: 'the second row must scroll into reach, not be clipped away',
    );
  });

  testWidgets('the sheet offers both rows from the design', (tester) async {
    await _open(tester);

    expect(find.text('Start a workout'), findsOneWidget);
    expect(find.text('AI Workout Generator'), findsOneWidget);
    expect(find.text('Log a workout'), findsOneWidget);
  });

  testWidgets('the row says what it does, not how it is implemented', (
    tester,
  ) async {
    // "Log manually" described an implementation detail, and it stopped being
    // only a one-off path the moment it could build a plan.
    await _open(tester);

    expect(find.text('Log a workout'), findsOneWidget);
    expect(find.text('Log manually'), findsNothing);
  });

  testWidgets('log manually is live now that the picker exists', (
    tester,
  ) async {
    // It was inert while the exercise library was a later slice. The library
    // and the sessions endpoint both exist now, so "Coming soon" would be
    // saying the capability is missing when it is not.
    await _open(tester);

    expect(find.text('Coming soon'), findsNothing);

    final row = tester.widget<InkWell>(find.byKey(const Key('start.manual')));
    expect(row.onTap, isNotNull);
  });

  testWidgets('log manually opens the setup screen', (tester) async {
    // The library is now a step further in: the setup screen is where the
    // split, length and injuries that describe the workout are shown, and
    // its own button opens the picker.
    await _open(tester);

    await tester.tap(find.byKey(const Key('start.manual')));
    // Pumped rather than settled: a regression that pushes the library
    // instead lands on a progress indicator that animates forever, and
    // pumpAndSettle would report a timeout rather than which screen arrived.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(WorkoutSetupScreen), findsOneWidget);
    expect(
      find.byType(ExerciseListScreen),
      findsNothing,
      reason: 'the picker is reached from the setup screen, not the sheet',
    );

    // The sheet must have been popped, not left stacked underneath: a
    // Navigator route that is merely covered by an opaque route above it is
    // absent from find.text either way, so the only way to tell is to go
    // back and see what resurfaces.
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Start a workout'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the generator row is tappable', (tester) async {
    await _open(tester);

    final row = tester.widget<InkWell>(
      find.byKey(const Key('start.generator')),
    );
    expect(row.onTap, isNotNull);
  });

  testWidgets('the close button dismisses the sheet', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('start.close')));
    await tester.pumpAndSettle();
    expect(find.text('Start a workout'), findsNothing);
  });

  testWidgets('the generator row opens the generator', (tester) async {
    // find.text('AI Workout Generator') alone would pass even with a no-op
    // onTap: the row itself carries that label. Assert the screen actually
    // arrives.
    await _open(tester);

    await tester.tap(find.byKey(const Key('start.generator')));
    await tester.pumpAndSettle();

    expect(find.byType(GeneratorScreen), findsOneWidget);

    // The sheet must have been popped, not left stacked underneath: a
    // Navigator route that is merely covered by an opaque route above it
    // is still absent from find.text regardless of whether it was popped,
    // so the only way to tell the two apart is to go back and see what
    // resurfaces.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Start a workout'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  group('the pain question', () {
    const pending = PendingOutcome(
      sessionId: 31,
      sessionDate: '2026-09-21',
      planName: null,
    );
    const question = 'How did your last workout leave you?';

    testWidgets('is asked before the start sheet when a session is pending', (
      tester,
    ) async {
      await _open(tester, pending: pending);

      expect(find.text(question), findsOneWidget);
      expect(find.text('Start a workout'), findsNothing);

      await tester.tap(find.byKey(const Key('outcome.skip')));
      await tester.pumpAndSettle();

      expect(find.text(question), findsNothing);
      expect(find.text('Start a workout'), findsOneWidget);
    });

    testWidgets('is not asked when nothing is pending', (tester) async {
      await _open(tester);
      expect(find.text(question), findsNothing);
      expect(find.text('Start a workout'), findsOneWidget);
    });

    testWidgets('a failed lookup still opens the start sheet', (tester) async {
      await _open(
        tester,
        pendingError: const ApiException('NETWORK_ERROR', 'unreachable'),
      );
      expect(find.text(question), findsNothing);
      expect(find.text('Start a workout'), findsOneWidget);
    });

    testWidgets('a lookup that never answers gives up after three seconds', (
      tester,
    ) async {
      await _open(tester, pendingFuture: Completer<PendingOutcome?>().future);
      expect(find.text('Start a workout'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text(question), findsNothing);
      expect(find.text('Start a workout'), findsOneWidget);
    });

    testWidgets(
      'a second tap while the lookup is in flight does not start a second '
      'chain',
      (tester) async {
        // The first tap's lookup is still in flight when the second tap
        // lands: nothing has resolved yet, so the base screen's button is
        // still the one thing on screen to hit.
        final lookup = Completer<PendingOutcome?>();
        await _open(tester, pendingFuture: lookup.future);

        await tester.tap(find.text('open'));

        lookup.complete(pending);
        await tester.pumpAndSettle();

        // A second, unguarded chain would have stacked a second outcome
        // sheet on top of the first once both resolved pending.
        expect(find.text(question), findsOneWidget);

        await tester.tap(find.byKey(const Key('outcome.skip')));
        await tester.pumpAndSettle();

        // Likewise for a second start sheet stacked on top of the first.
        expect(find.text('Start a workout'), findsOneWidget);

        // The guard must release once the chain ends, not stay set forever:
        // the next tap should open a fresh chain rather than being silently
        // swallowed.
        await tester.tap(find.byKey(const Key('start.close')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text(question), findsOneWidget);
      },
    );

    /// Serves the outcome POST at `/api/v1/sessions/31/outcome` -- 31 being
    /// `pending`'s sessionId above -- with [status] and, on success, the
    /// shape `recordOutcome` expects back.
    MockClient outcomeClient(int status) => MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/sessions/31/outcome') {
        if (status == 201) {
          return http.Response('{"data":{"outcome":{}}}', 201);
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'INTERNAL', 'message': 'x'},
          }),
          status,
        );
      }
      return http.Response('{"data":{}}', 200);
    });

    testWidgets(
      'answering "None" and saving opens the start sheet with no notice',
      (tester) async {
        await _open(tester, pending: pending, client: outcomeClient(201));

        await tester.tap(find.byKey(const Key('outcome.pain.none')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('outcome.submit')));
        await tester.pumpAndSettle();

        expect(find.text('Start a workout'), findsOneWidget);
        expect(find.byKey(const Key('start.notice')), findsNothing);
      },
    );

    testWidgets(
      'answering "None" when the save fails shows the notice on the start '
      'sheet',
      (tester) async {
        await _open(tester, pending: pending, client: outcomeClient(500));

        await tester.tap(find.byKey(const Key('outcome.pain.none')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('outcome.submit')));
        await tester.pumpAndSettle();

        expect(find.text('Start a workout'), findsOneWidget);
        expect(find.text(outcomeNotSavedMessage).hitTestable(), findsOneWidget);
      },
    );
  });
}
