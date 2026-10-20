import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/exercise_alternative.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/exercise_swap_sheet.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';

const _alt = ExerciseAlternative(
  exerciseId: 12,
  name: 'Push-up',
  muscleGroup: 'pectorals',
  equipment: 'Bodyweight',
);

const _plan = WorkoutPlan(
  planId: 1,
  name: 'P',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [],
);

/// A minimal [PlanRepository] whose swap always fails, so the sheet's error
/// path can be exercised without a mock framework — the interface is small
/// enough to implement directly.
class _FailingRepo implements PlanRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan?> activePlan() async => null;

  @override
  Future<List<ExerciseAlternative>> alternatives(
    int planExerciseId, {
    String? q,
    bool bodyweightOnly = false,
  }) async => const [];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async =>
      throw const ApiException(
        'EXERCISE_NOT_ALLOWED',
        'That exercise is not available for this plan.',
      );

  @override
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    int? sessionLengthMin,
    bool replaceCustomPlan = false,
  }) async =>
      throw UnimplementedError('the swap sheet never regenerates a plan');

  @override
  Future<WorkoutPlan> planFromSession({
    required int sessionId,
    String? splitStyle,
    int? dayNo,
  }) async => throw UnimplementedError(
    'the swap sheet never sends a workout to the plan',
  );
}

/// What the catalogue knows about the alternative under preview.
const _detail = ExerciseDetail(
  exerciseId: 12,
  name: 'Push-up',
  muscleGroup: 'pectorals',
  equipment: 'Bodyweight',
  thumbnailUrl: null,
  animationUrl: '/media/push-up.gif',
  cues: ['Set your hands under your shoulders'],
);

/// Records every swap it is asked for, so a test can prove one did *not*
/// happen — the point of putting a preview in front of it.
class _RecordingRepo implements PlanRepository {
  final swaps = <({int planExerciseId, int exerciseId})>[];

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan?> activePlan() async => _plan;

  @override
  Future<List<ExerciseAlternative>> alternatives(
    int planExerciseId, {
    String? q,
    bool bodyweightOnly = false,
  }) async => const [_alt];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async {
    swaps.add((planExerciseId: planExerciseId, exerciseId: exerciseId));
    return _plan;
  }

  @override
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    int? sessionLengthMin,
    bool replaceCustomPlan = false,
  }) async =>
      throw UnimplementedError('the swap sheet never regenerates a plan');

  @override
  Future<WorkoutPlan> planFromSession({
    required int sessionId,
    String? splitStyle,
    int? dayNo,
  }) async => throw UnimplementedError(
    'the swap sheet never sends a workout to the plan',
  );
}

/// Pumps the sheet with a repository that records swaps and a catalogue that
/// answers with [_detail].
Future<_RecordingRepo> _pumpWithPreview(WidgetTester tester) async {
  final repo = _RecordingRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWithValue(repo),
        alternativesProvider.overrideWith((ref, key) async => const [_alt]),
        exerciseDetailProvider.overrideWith((ref, id) async => _detail),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ExerciseSwapSheet(
            planExerciseId: 77,
            exerciseName: 'Cable Fly',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// A [PlanRepository] whose swap always succeeds immediately.
class _SucceedingRepo implements PlanRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan?> activePlan() async => _plan;

  @override
  Future<List<ExerciseAlternative>> alternatives(
    int planExerciseId, {
    String? q,
    bool bodyweightOnly = false,
  }) async => const [_alt];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async => _plan;

  @override
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    int? sessionLengthMin,
    bool replaceCustomPlan = false,
  }) async =>
      throw UnimplementedError('the swap sheet never regenerates a plan');

  @override
  Future<WorkoutPlan> planFromSession({
    required int sessionId,
    String? splitStyle,
    int? dayNo,
  }) async => throw UnimplementedError(
    'the swap sheet never sends a workout to the plan',
  );
}

/// A [PlanRepository] whose swap does not resolve until [completer] does —
/// lets a test dismiss the sheet while the request is still in flight.
class _SlowRepo implements PlanRepository {
  _SlowRepo(this.completer);

  final Completer<WorkoutPlan> completer;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan?> activePlan() async => _plan;

  @override
  Future<List<ExerciseAlternative>> alternatives(
    int planExerciseId, {
    String? q,
    bool bodyweightOnly = false,
  }) async => const [_alt];

  @override
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) =>
      completer.future;

  @override
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    int? sessionLengthMin,
    bool replaceCustomPlan = false,
  }) async =>
      throw UnimplementedError('the swap sheet never regenerates a plan');

  @override
  Future<WorkoutPlan> planFromSession({
    required int sessionId,
    String? splitStyle,
    int? dayNo,
  }) async => throw UnimplementedError(
    'the swap sheet never sends a workout to the plan',
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<ExerciseAlternative> rows, {
  VoidCallback? onGoToProfile,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [alternativesProvider.overrideWith((ref, key) async => rows)],
      child: MaterialApp(
        home: Scaffold(
          body: ExerciseSwapSheet(
            planExerciseId: 77,
            exerciseName: 'Cable Fly',
            onGoToProfile: onGoToProfile,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A Pixel-class phone, so a fraction-of-the-screen height means something.
const _screen = Size(1080, 2340);
const _dpr = 2.625;

List<ExerciseAlternative> _many(int n) => List.generate(
  n,
  (i) => ExerciseAlternative(
    exerciseId: i + 1,
    name: 'Alternative ${i + 1}',
    muscleGroup: 'pectorals',
    equipment: 'Barbell',
  ),
);

/// Opens the sheet the way [PlanScreen] does — through a real modal route.
///
/// The bare [_pump] above hands the sheet a Scaffold body, whose tight
/// constraints would stretch any height it asks for to fill the screen. Only
/// a modal sheet's loose constraints let it size itself, so every height
/// assertion has to come through here.
Future<double> _pumpAsSheet(
  WidgetTester tester,
  List<ExerciseAlternative> rows, {
  double keyboard = 0,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = _dpr;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * _dpr);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [alternativesProvider.overrideWith((ref, key) async => rows)],
      child: MaterialApp(
        // A fresh key per call: without it a second `_pumpAsSheet` in the same
        // test reuses the Navigator's element, which still holds the first
        // sheet's route — the "open" button would then be behind a modal
        // barrier and the tap would dismiss the sheet instead.
        key: ValueKey('${rows.length}:$keyboard'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ExerciseSwapSheet(
                  planExerciseId: 77,
                  exerciseName: 'Cable Fly',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(ExerciseSwapSheet)).height;
}

/// The sheet as the Plan tab and the logger open it -- a real modal route --
/// with its swap held on [completer], so a test can try to close it while the
/// server is still answering. [result] receives whatever the route pops.
Future<void> _pumpModalSheet(
  WidgetTester tester, {
  required Completer<WorkoutPlan> completer,
  required void Function(String?) result,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWithValue(_SlowRepo(completer)),
        alternativesProvider.overrideWith((ref, key) async => const [_alt]),
        exerciseDetailProvider.overrideWith((ref, id) async => _detail),
        activePlanProvider.overrideWith((ref) async => _plan),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ExerciseSwapSheet(
                  planExerciseId: 77,
                  exerciseName: 'Cable Fly',
                ),
              ).then(result),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('swap.alt.12')));
  await tester.pumpAndSettle();
}

/// Drags the sheet down from its top edge, well past the point where a
/// modal bottom sheet closes.
Future<void> _dragSheetDown(WidgetTester tester) async {
  final top = tester.getRect(find.byType(ExerciseSwapSheet)).topCenter;
  await tester.dragFrom(top + const Offset(0, 8), const Offset(0, 600));
}

void main() {
  testWidgets('names the exercise being replaced', (tester) async {
    await _pump(tester, const [_alt]);

    expect(find.text('Replace Cable Fly'), findsOneWidget);
  });

  // The sheet opens from the Plan tab and from inside a workout, and from the
  // workout a swap reads like a one-off. It is not: the plan row changes for
  // every later session too, so the sheet says so under its heading.
  testWidgets('says under the heading that the swap changes the plan', (
    tester,
  ) async {
    await _pump(tester, const [_alt]);

    final caption = find.text('Changes your plan from now on, not just today.');
    expect(caption, findsOneWidget);
    expect(
      tester.getTopLeft(caption).dy,
      greaterThan(tester.getBottomLeft(find.text('Replace Cable Fly')).dy - 1),
    );
  });

  testWidgets('lists the alternatives', (tester) async {
    await _pump(tester, const [_alt]);

    expect(find.text('Push-up'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);
  });

  testWidgets('explains an empty pool rather than showing a blank list', (
    tester,
  ) async {
    await _pump(tester, const []);

    // Reachable in production: delts has no body-weight strength exercises at
    // all, so a user who owns nothing gets zero alternatives for a shoulder.
    expect(find.textContaining('Nothing you can do'), findsOneWidget);
  });

  testWidgets('a failed swap keeps the sheet open with the message', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alternativesProvider.overrideWith((ref, key) async => const [_alt]),
          planRepositoryProvider.overrideWithValue(_FailingRepo()),
          exerciseDetailProvider.overrideWith((ref, id) async => _detail),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExerciseSwapSheet(
              planExerciseId: 77,
              exerciseName: 'Cable Fly',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('swap.preview.confirm')));
    await tester.pumpAndSettle();

    expect(
      find.byType(ExerciseSwapSheet),
      findsOneWidget,
      reason: 'closing would discard the choice the user just made',
    );
    expect(
      find.byKey(const Key('swap.preview')),
      findsOneWidget,
      reason:
          'the rejected candidate stays on screen to be retried or '
          'backed out of, rather than dumping the user in the list',
    );
    expect(find.textContaining('not available'), findsOneWidget);
  });

  testWidgets('points at Profile even when the list is not empty', (
    tester,
  ) async {
    await _pump(tester, const [_alt]);

    // The pool is filtered to the equipment picked at onboarding, and until
    // the list runs dry nothing on the sheet says so: a user who owns a cable
    // machine reads a page of body-weight rows as the whole catalogue rather
    // than as the consequence of a setting they can change.
    expect(find.textContaining("Don't see your equipment?"), findsOneWidget);
  });

  testWidgets('tapping the equipment note asks for the Profile tab', (
    tester,
  ) async {
    var asked = 0;
    await _pump(tester, const [_alt], onGoToProfile: () => asked++);

    await tester.tap(find.byKey(const Key('swap.equipmentHint')));
    await tester.pumpAndSettle();

    expect(asked, 1);
  });

  testWidgets(
    'the equipment note is inert when nothing wired a way to Profile',
    (tester) async {
      await _pump(tester, const [_alt]);

      // The advice still holds without a route to act on it — a sheet pumped
      // outside the shell has no tab to switch to — but a link that goes
      // nowhere is worse than plain text, so only the tappability drops.
      expect(find.byKey(const Key('swap.equipmentHint')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('swap.equipmentHint')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a successful swap invalidates every cached alternatives list, not just this row',
    (tester) async {
      var fetches = 0;
      final container = ProviderContainer(
        overrides: [
          alternativesProvider.overrideWith((ref, key) async {
            fetches++;
            return const [_alt];
          }),
          planRepositoryProvider.overrideWithValue(_SucceedingRepo()),
          exerciseDetailProvider.overrideWith((ref, id) async => _detail),
        ],
      );
      addTearDown(container.dispose);

      // Held outside the sheet's widget tree, on the very key the sheet
      // itself watches, so it is not torn down when the sheet closes below —
      // isolating the family-wide invalidate in `_choose` from auto-dispose,
      // which would also eventually reclaim a genuinely-unwatched entry on
      // its own and could make this pass for the wrong reason.
      const key = (planExerciseId: 77, query: '');
      container.listen(alternativesProvider(key), (_, _) {});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: ExerciseSwapSheet(
                planExerciseId: 77,
                exerciseName: 'Cable Fly',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fetches, 1, reason: 'one fetch renders the initial list');

      await tester.tap(find.byKey(const Key('swap.alt.12')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('swap.preview.confirm')));
      await tester.pumpAndSettle();

      expect(
        fetches,
        2,
        reason:
            'a swap changes inPlanIds for every row in the plan, so every '
            'cached alternatives list — including this exact key — must be '
            'refetched, not just the row that changed',
      );
    },
  );

  testWidgets(
    'a swap in flight when the sheet is dismissed still refreshes the plan',
    (tester) async {
      final completer = Completer<WorkoutPlan>();
      var activePlanFetches = 0;
      final container = ProviderContainer(
        overrides: [
          planRepositoryProvider.overrideWithValue(_SlowRepo(completer)),
          exerciseDetailProvider.overrideWith((ref, id) async => _detail),
          alternativesProvider.overrideWith((ref, key) async => const [_alt]),
          activePlanProvider.overrideWith((ref) {
            activePlanFetches++;
            return Future.value(_plan);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Held outside the sheet's widget tree so it survives the sheet's
      // disposal below — asserting on the (by then disposed) sheet's own
      // state would prove nothing about whether the refresh actually reached
      // the provider.
      container.listen(activePlanProvider, (_, _) {});
      await container.read(activePlanProvider.future);
      expect(activePlanFetches, 1);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: ExerciseSwapSheet(
                planExerciseId: 77,
                exerciseName: 'Cable Fly',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('swap.alt.12')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('swap.preview.confirm')));
      await tester.pump(); // starts the swap; it awaits the completer, so it does not resolve yet

      // Dismiss the sheet by replacing the whole widget tree under it — the
      // sheet's State is disposed while its swap() call is still in flight,
      // exactly as it would be if the user swiped the sheet away mid-request.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      await tester.pump();

      completer.complete(_plan);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'completing the swap after disposal must not throw',
      );
      expect(
        activePlanFetches,
        2,
        reason: 'the refresh must survive the sheet being disposed mid-request',
      );
    },
  );

  testWidgets(
    'opens at the same height whether there are two candidates or twelve',
    (tester) async {
      final two = await _pumpAsSheet(tester, _many(2));
      final twelve = await _pumpAsSheet(tester, _many(12));

      // The point of the fixed height: a muscle with a dozen alternatives used
      // to grow the sheet until it covered the plan entirely, so the same
      // action looked like a different screen depending on the exercise.
      expect(twelve, two);
      final screen = _screen.height / _dpr;
      expect(
        twelve / screen,
        closeTo(0.52, 0.01),
        reason:
            'the fraction is tuned to clear the Exercises heading below '
            'the Plan tab\'s WeekStrip and SessionCard, with headroom for a '
            'wrapped plan name -- see exercise_swap_sheet.dart',
      );
    },
  );

  testWidgets('a list too long for the sheet scrolls inside it', (
    tester,
  ) async {
    await _pumpAsSheet(tester, _many(12));

    expect(
      find.text('Alternative 12'),
      findsNothing,
      reason: 'twelve rows cannot fit; the last must start off-screen',
    );

    await tester.scrollUntilVisible(
      find.text('Alternative 12'),
      200,
      // Scoped to the list: the search field's EditableText is a Scrollable
      // too, so a sheet-wide finder matches two.
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alternative 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gives the keyboard room instead of overflowing behind it', (
    tester,
  ) async {
    // Guards the fix rather than driving it: a content-sized sheet already
    // survived this, but a rigid two thirds would not. The route anchors the
    // sheet to the bottom of the screen and never lifts it, so with a 400pt
    // keyboard up a 66%-tall box leaves ~170pt for a title, a search field,
    // a chip, a list and a footnote — a RenderFlex overflow, and rows the
    // user cannot reach.
    const keyboard = 400.0;
    await _pumpAsSheet(tester, _many(12), keyboard: keyboard);

    final screen = _screen.height / _dpr;
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.text('Alternative 1')).dy,
      lessThanOrEqualTo(screen - keyboard),
      reason: 'the first row has to sit above the keyboard, not behind it',
    );
  });

  testWidgets('the demo is not stretched far past the pixels it has', (
    tester,
  ) async {
    // Every animation in the store is 180x180. Filling the pane asked the
    // renderer for roughly five times that on a modern phone, which is the
    // whole of the blur — there is no more detail in the file to find.
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);

    await _pumpWithPreview(tester);
    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();

    final painted = tester.getSize(find.byType(Image)).width * _dpr;
    expect(
      painted,
      lessThanOrEqualTo(180 * 3),
      reason:
          'asking for more than 3x the source resolution buys nothing '
          'but blur',
    );
    expect(
      painted,
      greaterThan(180.0),
      reason: 'nor should it be shrunk below the detail it does have',
    );
  });

  testWidgets('tapping an alternative previews it instead of swapping it', (
    tester,
  ) async {
    final repo = await _pumpWithPreview(tester);

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();

    expect(
      repo.swaps,
      isEmpty,
      reason: 'a tap used to be the commitment; now it only opens a look',
    );
    expect(find.byKey(const Key('swap.preview')), findsOneWidget);
    expect(
      find.byKey(const Key('swap.search')),
      findsNothing,
      reason: 'the preview takes the whole sheet, list and search included',
    );
  });

  testWidgets('the preview plays the catalogue demo', (tester) async {
    await _pumpWithPreview(tester);

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as NetworkImage).url,
      'http://test.local/media/push-up.gif',
      reason: 'the demo is the whole point of the preview',
    );
  });

  testWidgets('confirming from the preview is what swaps', (tester) async {
    final repo = await _pumpWithPreview(tester);

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('swap.preview.confirm')));
    await tester.pumpAndSettle();

    expect(repo.swaps, [(planExerciseId: 77, exerciseId: 12)]);
  });

  testWidgets('backing out of the preview keeps the search that found it', (
    tester,
  ) async {
    await _pumpWithPreview(tester);
    await tester.enterText(find.byKey(const Key('swap.search')), 'push');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap.alt.12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('swap.preview.back')));
    await tester.pumpAndSettle();

    // Re-running the search after a look at one candidate would be tedious
    // exactly when someone is comparing several.
    expect(find.text('push'), findsOneWidget);
    expect(find.byKey(const Key('swap.alt.12')), findsOneWidget);
  });
  group('while a swap is in flight the sheet stays open', () {
    // Closing it mid-request used to let the swap land with nobody to say
    // so: the plan changed under a screen that thought it had cancelled.
    late Completer<WorkoutPlan> completer;
    late List<String?> popped;

    Future<void> confirm(WidgetTester tester) async {
      completer = Completer<WorkoutPlan>();
      popped = [];
      await _pumpModalSheet(tester, completer: completer, result: popped.add);
      await tester.tap(find.byKey(const Key('swap.preview.confirm')));
      // Not pumpAndSettle: the busy button spins until the swap lands.
      await tester.pump();
    }

    Future<void> landSwap(WidgetTester tester) async {
      expect(find.byType(ExerciseSwapSheet), findsOneWidget);
      expect(popped, isEmpty);
      completer.complete(_plan);
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseSwapSheet), findsNothing);
      expect(popped, ['Push-up']);
    }

    testWidgets('a tap on the barrier', (tester) async {
      await confirm(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 500));
      await landSwap(tester);
    });

    testWidgets('system back', (tester) async {
      await confirm(tester);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      await landSwap(tester);
    });

    testWidgets('a drag down', (tester) async {
      await confirm(tester);
      await _dragSheetDown(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await landSwap(tester);
    });
  });

  group('on a 320 dp phone at large text', () {
    /// The sheet through a real modal route, as the logger and the Plan tab
    /// open it, on a 320 x 640 phone at twice the text size.
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alternativesProvider.overrideWith((ref, key) async => _many(3)),
            exerciseDetailProvider.overrideWith((ref, id) async => _detail),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ExerciseSwapSheet(
                      planExerciseId: 77,
                      exerciseName: 'Barbell bench press',
                      onGoToProfile: () {},
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder sheetScroll() => find
        .descendant(
          of: find.byType(ExerciseSwapSheet),
          matching: find.byType(Scrollable),
        )
        .first;

    // The heading, the search field and the equipment note were a fixed
    // column around the list, which at 2x is taller than the sheet: the
    // column overflowed by hundreds of pixels and the list had no room at
    // all. The whole pane scrolls instead, and every part of it is reachable.
    testWidgets('the list pane scrolls as one instead of overflowing', (
      tester,
    ) async {
      await open(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Replace Barbell bench press'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('swap.alt.3')),
        100,
        scrollable: sheetScroll(),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('swap.equipmentHint.link')),
        100,
        scrollable: sheetScroll(),
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('swap.alt.3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('swap.alt.3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('swap.preview')), findsOneWidget);
    });

    testWidgets('the preview fits, with a full-size way back', (tester) async {
      await open(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('swap.alt.1')),
        100,
        scrollable: sheetScroll(),
      );
      await tester.tap(find.byKey(const Key('swap.alt.1')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final back = tester.getSize(find.byKey(const Key('swap.preview.back')));
      expect(back.width, greaterThanOrEqualTo(48));
      expect(back.height, greaterThanOrEqualTo(48));
      expect(
        find.byKey(const Key('swap.preview.confirm')).hitTestable(),
        findsOneWidget,
      );
    });
  });

  // The scroll-everything layout is for text too large for the pinned one,
  // not for small phones: at 1x the heading, search field and equipment note
  // fit on any portrait phone 640 dp tall, and the note has to stay in view
  // under a full list -- see the equipment note in the sheet.
  for (final phone in const [Size(360, 640), Size(375, 667)]) {
    testWidgets(
      'on a ${phone.width.toInt()} x ${phone.height.toInt()} phone at 1x the '
      'equipment note stays pinned under a full list',
      (tester) async {
        tester.view.physicalSize = phone;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              alternativesProvider.overrideWith((ref, key) async => _many(12)),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ExerciseSwapSheet(
                        planExerciseId: 77,
                        exerciseName: 'Cable Fly',
                        onGoToProfile: () {},
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('swap.pane.scroll')), findsNothing);
        expect(
          find.byKey(const Key('swap.equipmentHint.link')).hitTestable(),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('with no swap in flight a drag down still closes the sheet', (
    tester,
  ) async {
    final popped = <String?>[];
    await _pumpModalSheet(
      tester,
      completer: Completer<WorkoutPlan>(),
      result: popped.add,
    );

    await _dragSheetDown(tester);
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseSwapSheet), findsNothing);
    expect(popped, [null]);
  });
}
