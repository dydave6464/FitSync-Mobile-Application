import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_logger_screen.dart';
import 'package:fitsync/features/sessions/presentation/workout_draft.dart';
import 'package:fitsync/features/sessions/presentation/workout_review_screen.dart';

const _squat = ExerciseSummary(
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  equipment: 'dumbbell',
  thumbnailUrl: null,
);
const _fly = ExerciseSummary(
  exerciseId: 202,
  name: 'Cable fly',
  muscleGroup: 'pectorals',
  equipment: 'cable',
  thumbnailUrl: null,
);
const _press = ExerciseSummary(
  exerciseId: 303,
  name: 'Bench press',
  muscleGroup: 'pectorals',
  equipment: 'barbell',
  thumbnailUrl: null,
);

class FakeExerciseRepository implements ExerciseRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Records what the review screen asked the server to start.
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({this.error, this.existing});

  final Object? error;

  /// A session already in progress, as `GET /sessions/active` would report.
  final ActiveSession? existing;

  List<int>? startedWith;
  int startCalls = 0;
  int abandoned = 0;

  /// Mutable, so abandoning the held session actually frees it the way the
  /// server does -- a fake that kept answering with it would let a test pass
  /// against a start that could never succeed in practice.
  late ActiveSession? _held = existing;

  @override
  Future<ActiveSession?> active() async => _held;

  @override
  Future<void> abandon(int sessionId) async {
    abandoned += 1;
    _held = null;
  }

  @override
  Future<ActiveSession> start({List<int>? exerciseIds}) async {
    startCalls += 1;
    startedWith = exerciseIds;
    if (error != null) throw error!;
    return ActiveSession(
      sessionId: 9,
      status: 'in_progress',
      sessionDate: '2026-09-14',
      startedAt: DateTime.now(),
      exercises: [
        for (final (index, id) in (exerciseIds ?? const <int>[]).indexed)
          PlanExercise(
            planExerciseId: index + 1,
            exerciseId: id,
            name: 'Ex $id',
            muscleGroup: 'x',
            orderNo: index + 1,
            targetSets: 3,
            targetReps: '8-12',
          ),
      ],
    );
  }

  @override
  Future<Map<int, LastPerformance>> lastPerformance(List<int> ids) async =>
      const {};

  @override
  Future<Set<String>> completedThisWeek() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Seeds the draft the library would have filled in.
class _Picked extends WorkoutDraftNotifier {
  _Picked(this.picks);
  final List<ExerciseSummary> picks;

  @override
  List<ExerciseSummary> build() => picks;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<ExerciseSummary> picks,
  FakeSessionRepository? sessions,
  bool overLibrary = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      exerciseRepositoryProvider.overrideWithValue(FakeExerciseRepository()),
      sessionRepositoryProvider.overrideWithValue(
        sessions ?? FakeSessionRepository(),
      ),
      workoutDraftProvider.overrideWith(() => _Picked(picks)),
      // A manual session has no plan; the logger must not need one.
      activePlanProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: fsLightTheme(),
        // With [overLibrary], a stand-in for the library sits underneath, so
        // leaving the screen has somewhere to go, as it does in the app.
        home: overLibrary
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const WorkoutReviewScreen(),
                      ),
                    ),
                    child: const Text('Library'),
                  ),
                ),
              )
            : const WorkoutReviewScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (overLibrary) {
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
  }
  return container;
}

ActiveSession _openWorkout() => ActiveSession(
  sessionId: 4,
  status: 'in_progress',
  sessionDate: '2026-09-14',
  startedAt: DateTime.now(),
);

Finder _start() => find.byKey(const Key('review.start'));

/// Drags the row's handle onto [target]'s position and drops it there.
///
/// A single `tester.drag` is one synthetic move, which ReorderableListView
/// does not treat as a reorder -- it tracks the pointer across frames to work
/// out which slot the row is over. Stepping the gesture and pumping between
/// moves is what a real finger looks like to it.
///
/// [grabAt] is where on the handle the finger lands, measured from its top
/// left corner; by default it is the centre.
Future<void> _dragOnto(
  WidgetTester tester,
  Key handle,
  Key target, {
  Offset? grabAt,
}) async {
  final from = grabAt == null
      ? tester.getCenter(find.byKey(handle))
      : tester.getTopLeft(find.byKey(handle)) + grabAt;
  final to = tester.getCenter(find.byKey(target));

  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 16));

  // The first move has to clear kTouchSlop or the drag is never recognised,
  // so the step size is chosen to exceed it rather than by splitting the
  // distance into a fixed number of parts.
  final total = to - from;
  final steps = (total.distance / (kTouchSlop * 2)).ceil().clamp(2, 40);
  final step = total / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }

  await gesture.up();
  await tester.pumpAndSettle();
}

Finder _more(int id) => find.byKey(Key('review.more.$id'));

/// Opens a row's ⋮ menu and picks [item] from it.
Future<void> _pickFromMenu(WidgetTester tester, int id, String item) async {
  await tester.tap(_more(id));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('review.$item.$id')));
  await tester.pumpAndSettle();
}

/// Whether a row's ⋮ menu item can be chosen, read off the open menu.
bool _menuItemEnabled(WidgetTester tester, String item, int id) => tester
    .widget<PopupMenuItem<Object?>>(find.byKey(Key('review.$item.$id')))
    .enabled;

void main() {
  testWidgets('lists the picks in the order they will be trained', (
    tester,
  ) async {
    await _pump(tester, picks: const [_squat, _fly, _press]);

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Cable fly'), findsOneWidget);
    expect(find.text('Bench press'), findsOneWidget);

    // Top-to-bottom on screen is the order the logger walks, so the screen
    // has to render it in that order rather than in id or name order.
    final positions = [
      tester.getTopLeft(find.text('Goblet squat')).dy,
      tester.getTopLeft(find.text('Cable fly')).dy,
      tester.getTopLeft(find.text('Bench press')).dy,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
  });

  testWidgets('says how many exercises the workout holds', (tester) async {
    await _pump(tester, picks: const [_squat, _fly]);

    expect(find.textContaining('2 exercises'), findsOneWidget);
  });

  testWidgets('one exercise is not called "1 exercises"', (tester) async {
    await _pump(tester, picks: const [_squat]);

    expect(find.textContaining('1 exercise'), findsOneWidget);
    expect(find.textContaining('1 exercises'), findsNothing);
  });

  testWidgets('removing a row drops it from the workout', (tester) async {
    final container = await _pump(tester, picks: const [_squat, _fly]);

    await _pickFromMenu(tester, 101, 'remove');

    expect(find.text('Goblet squat'), findsNothing);
    expect(container.read(workoutDraftProvider).exerciseIds, [202]);
  });

  testWidgets('starting sends the ids in the order shown', (tester) async {
    final sessions = FakeSessionRepository();
    await _pump(
      tester,
      picks: const [_squat, _fly, _press],
      sessions: sessions,
    );

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(sessions.startedWith, [101, 202, 303]);
  });

  testWidgets('dragging an exercise to the top starts it first', (
    tester,
  ) async {
    // The whole reason the screen is draggable: order_no comes from this, and
    // before the drag the order was only "whichever row was tapped first".
    final sessions = FakeSessionRepository();
    await _pump(
      tester,
      picks: const [_squat, _fly, _press],
      sessions: sessions,
    );

    await _dragOnto(
      tester,
      const Key('review.drag.303'),
      const Key('review.drag.101'),
    );

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(
      sessions.startedWith!.first,
      303,
      reason: 'the dragged exercise must be trained first',
    );
  });

  testWidgets('starting opens the logger', (tester) async {
    await _pump(tester, picks: const [_squat]);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  testWidgets('a started workout leaves nothing drafted', (tester) async {
    final container = await _pump(tester, picks: const [_squat]);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(container.read(workoutDraftProvider), isEmpty);
  });

  testWidgets('a failed start keeps the picks so they can be retried', (
    tester,
  ) async {
    final sessions = FakeSessionRepository(
      error: const ApiException('NETWORK_ERROR', 'Could not reach the server.'),
    );
    final container = await _pump(
      tester,
      picks: const [_squat, _fly],
      sessions: sessions,
    );

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server.'), findsOneWidget);
    expect(container.read(workoutDraftProvider).exerciseIds, [
      101,
      202,
    ], reason: 'choosing them all again is not a retry');
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  testWidgets('a workout already open is named rather than silently replaced', (
    tester,
  ) async {
    // The server is idempotent here: it returns the running session and
    // ignores the list, so opening the logger anyway would drop everything
    // just picked and show a workout the user did not choose.
    final sessions = FakeSessionRepository(existing: _openWorkout());
    await _pump(tester, picks: const [_squat], sessions: sessions);

    await tester.tap(_start());
    await tester.pumpAndSettle();

    expect(find.textContaining('already have a workout open'), findsOneWidget);
    expect(sessions.startCalls, 0);
    expect(find.byType(SessionLoggerScreen), findsNothing);
  });

  testWidgets('the workout in the way can be opened from the message', (
    tester,
  ) async {
    final sessions = FakeSessionRepository(existing: _openWorkout());
    await _pump(tester, picks: const [_squat], sessions: sessions);

    await tester.tap(_start());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open it'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionLoggerScreen), findsOneWidget);
    expect(sessions.startCalls, 0, reason: 'opening is not starting');
    expect(sessions.abandoned, 0, reason: 'opening throws nothing away');
  });

  testWidgets('the workout in the way can be discarded and this one started', (
    tester,
  ) async {
    // Without this the message was a dead end: the only way out was to find
    // the old session in another tab and close it from inside the logger.
    final sessions = FakeSessionRepository(existing: _openWorkout());
    await _pump(tester, picks: const [_squat, _fly], sessions: sessions);

    await tester.tap(_start());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard it & start'));
    await tester.pumpAndSettle();

    expect(sessions.abandoned, 1);
    expect(sessions.startedWith, [101, 202], reason: 'the picks were kept');
    expect(find.byType(SessionLoggerScreen), findsOneWidget);
  });

  testWidgets('backing out of the message leaves both workouts alone', (
    tester,
  ) async {
    final sessions = FakeSessionRepository(existing: _openWorkout());
    final container = await _pump(
      tester,
      picks: const [_squat],
      sessions: sessions,
    );

    await tester.tap(_start());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(sessions.abandoned, 0);
    expect(sessions.startCalls, 0);
    expect(container.read(workoutDraftProvider).exerciseIds, [
      101,
    ], reason: 'the picks must survive a cancelled start');
  });

  testWidgets('an emptied workout cannot be started', (tester) async {
    await _pump(tester, picks: const [_squat]);

    await _pickFromMenu(tester, 101, 'remove');

    expect(
      tester.widget<FsButton>(_start()).onPressed,
      isNull,
      reason: 'a workout of no exercises is not a workout',
    );
  });

  group('reordering without dragging', () {
    testWidgets('each row has a named ⋮ button with a 48 dp target', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, picks: const [_squat, _fly]);

      // The tooltip is what TalkBack reads as the button's name.
      expect(find.byTooltip('More options for Goblet squat'), findsOneWidget);
      final size = tester.getSize(_more(101));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });

    testWidgets('Move up is off on the first row, Move down on the last', (
      tester,
    ) async {
      await _pump(tester, picks: const [_squat, _fly, _press]);

      await tester.tap(_more(101));
      await tester.pumpAndSettle();
      expect(_menuItemEnabled(tester, 'moveUp', 101), isFalse);
      expect(_menuItemEnabled(tester, 'moveDown', 101), isTrue);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(_more(303));
      await tester.pumpAndSettle();
      expect(_menuItemEnabled(tester, 'moveUp', 303), isTrue);
      expect(_menuItemEnabled(tester, 'moveDown', 303), isFalse);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(_more(202));
      await tester.pumpAndSettle();
      expect(_menuItemEnabled(tester, 'moveUp', 202), isTrue);
      expect(_menuItemEnabled(tester, 'moveDown', 202), isTrue);
    });

    testWidgets('Move down swaps a row with the one below it', (tester) async {
      final container = await _pump(
        tester,
        picks: const [_squat, _fly, _press],
      );

      await _pickFromMenu(tester, 101, 'moveDown');

      expect(container.read(workoutDraftProvider).exerciseIds, [202, 101, 303]);
    });

    testWidgets('Move up swaps a row with the one above it', (tester) async {
      final container = await _pump(
        tester,
        picks: const [_squat, _fly, _press],
      );

      await _pickFromMenu(tester, 303, 'moveUp');

      expect(container.read(workoutDraftProvider).exerciseIds, [101, 303, 202]);
    });

    testWidgets('a moved row is what starts in its new place', (tester) async {
      final sessions = FakeSessionRepository();
      await _pump(
        tester,
        picks: const [_squat, _fly, _press],
        sessions: sessions,
      );

      await _pickFromMenu(tester, 202, 'moveUp');
      await tester.tap(_start());
      await tester.pumpAndSettle();

      expect(sessions.startedWith, [202, 101, 303]);
    });
  });

  group('removing can be undone', () {
    testWidgets('removing says what went and offers Undo', (tester) async {
      await _pump(tester, picks: const [_squat, _fly, _press]);

      await _pickFromMenu(tester, 202, 'remove');

      expect(find.text('Removed Cable fly'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
    });

    testWidgets('Undo puts it back in the same position', (tester) async {
      final container = await _pump(
        tester,
        picks: const [_squat, _fly, _press],
      );

      await _pickFromMenu(tester, 202, 'remove');
      expect(container.read(workoutDraftProvider).exerciseIds, [101, 303]);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(container.read(workoutDraftProvider).exerciseIds, [101, 202, 303]);
      expect(find.text('Cable fly'), findsOneWidget);
    });

    testWidgets('Undo brings back the only exercise of an emptied workout', (
      tester,
    ) async {
      final container = await _pump(tester, picks: const [_squat]);

      await _pickFromMenu(tester, 101, 'remove');
      expect(find.text('Nothing in this workout yet.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(container.read(workoutDraftProvider).exerciseIds, [101]);
      expect(tester.widget<FsButton>(_start()).onPressed, isNotNull);
    });

    testWidgets('the Undo message goes away on its own', (tester) async {
      // A SnackBar with an action persists by default, which would leave the
      // message pinned over the Start button for as long as the screen stays.
      await _pump(tester, picks: const [_squat, _fly]);

      await _pickFromMenu(tester, 101, 'remove');
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('Removed Goblet squat'), findsNothing);
    });

    testWidgets('the Undo message stays up for screen-reader users', (
      tester,
    ) async {
      // Moving to Undo with TalkBack takes longer than the four seconds a
      // timed SnackBar gives, so with a screen reader on it must wait.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pump(tester, picks: const [_squat, _fly]);

      await _pickFromMenu(tester, 101, 'remove');
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('Removed Goblet squat'), findsOneWidget);
    });

    testWidgets('the Undo message does not follow the user off the screen', (
      tester,
    ) async {
      // Its Undo can do nothing once the screen is gone, so it must not be
      // left showing over the library.
      await _pump(tester, picks: const [_squat, _fly], overLibrary: true);

      await _pickFromMenu(tester, 101, 'remove');
      expect(find.text('Removed Goblet squat'), findsOneWidget);

      await tester.tap(find.byKey(const Key('review.addMore')));
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Removed Goblet squat'), findsNothing);
    });
  });

  group('the drag handle', () {
    testWidgets('has a 48 dp touch area and a screen-reader name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, picks: const [_squat, _fly]);

      final size = tester.getSize(find.byKey(const Key('review.drag.101')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Reorder Goblet squat'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('starts a drag from the edge of its touch area', (
      tester,
    ) async {
      // The 48 dp box has to catch the touch itself; otherwise only a finger
      // landing on the 20 dp glyph would count, and the bigger area would be
      // for show.
      final container = await _pump(
        tester,
        picks: const [_squat, _fly, _press],
      );

      await _dragOnto(
        tester,
        const Key('review.drag.303'),
        const Key('review.drag.101'),
        grabAt: const Offset(4, 4),
      );

      expect(container.read(workoutDraftProvider).exerciseIds, [303, 101, 202]);
    });

    testWidgets('keeps the icon the same size it was', (tester) async {
      await _pump(tester, picks: const [_squat]);

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('review.drag.101')),
          matching: find.byIcon(Icons.drag_indicator),
        ),
      );
      expect(icon.size, 20);
    });
  });

  testWidgets('the hint is not in the faint text colour', (tester) async {
    await _pump(tester, picks: const [_squat]);

    final hint = tester.widget<Text>(find.byKey(const Key('review.hint')));
    final t = fsLightTheme().extension<FsTokens>()!;
    expect(hint.style!.color, isNot(t.text3));
  });

  testWidgets('fits a 320 dp screen at 2.0× text, menu open too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, picks: const [_squat, _fly, _press]);
    expect(tester.takeException(), isNull);

    await tester.tap(_more(202));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('review.remove.202')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Removed Cable fly'), findsOneWidget);
  });
}
