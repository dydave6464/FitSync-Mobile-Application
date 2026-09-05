import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/home/presentation/nav_shell.dart';
import 'package:fitsync/features/plans/domain/exercise_alternative.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/plan_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/settings/presentation/settings_screen.dart';

/// Enough rows that the catalogue's list is taller than the test viewport,
/// so it actually has somewhere to scroll to.
const _exerciseCount = 30;

/// A hermetic stand-in for the real repository. Its `list` always answers
/// with the same full page (`hasMore` false), so scrolling never triggers a
/// pagination fetch that would complicate the scroll-position assertion.
class FakeExerciseRepository implements ExerciseRepository {
  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExercisePage> list({
    String? muscleGroup,
    String? equipment,
    int page = 1,
    int limit = 20,
  }) async =>
      ExercisePage(
        items: List.generate(
          _exerciseCount,
          (i) => ExerciseSummary(
            exerciseId: i + 1,
            name: 'Exercise ${i + 1}',
            muscleGroup: 'abs',
            equipment: 'body weight',
            thumbnailUrl: null,
          ),
        ),
        page: 1,
        limit: _exerciseCount,
        total: _exerciseCount,
      );

  @override
  Future<ExerciseDetail> byId(int id) async => throw UnimplementedError();

  @override
  Future<ExerciseFilters> filters() async =>
      const ExerciseFilters(muscleGroups: [], equipment: []);
}

/// Keeps the Profile tab off the secure-storage platform channel, mirroring
/// `StubProfileNotifier` in app_shell_test.dart.
class StubProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile> build() async => const Profile(
        userId: 7,
        email: 'juan@example.com',
        fullName: 'Juan Dela Cruz',
        onboardingCompleted: true,
        isPremium: false,
        notificationsEnabled: true,
        equipment: [],
        injuries: [],
      );
}

/// One row is enough to reach the swap sheet from the Train tab.
const _plan = WorkoutPlan(
  planId: 1,
  name: 'Week 1',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 601,
      exerciseId: 101,
      name: 'Goblet squat',
      muscleGroup: 'quadriceps',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
    ),
  ],
);

Future<void> _pumpShell(WidgetTester tester, {WorkoutPlan? plan}) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Defensive: nothing here should actually reach it, since every
          // tab's own data provider is overridden below, but a stray watch
          // must fail hermetically rather than hang on a real socket.
          apiClientProvider.overrideWithValue(ApiClient(
            baseUrl: 'http://test.local',
            tokens: TokenStore(backing: InMemorySecureStore()),
            client: MockClient((_) async => http.Response('{"data":{}}', 200)),
          )),
          // Train tab (PlanScreen). No plan keeps it on the simple empty
          // state, which is also what avoids a stray "Exercises" eyebrow
          // label competing with the Browse tab's AppBar title below.
          activePlanProvider.overrideWith((ref) async => plan),
          alternativesProvider.overrideWith((ref, key) async => const [
                ExerciseAlternative(
                  exerciseId: 12,
                  name: 'Push-up',
                  muscleGroup: 'quadriceps',
                  equipment: 'Bodyweight',
                ),
              ]),
          // Browse tab (ExerciseListScreen).
          exerciseRepositoryProvider.overrideWithValue(FakeExerciseRepository()),
          // Profile tab (SettingsScreen).
          profileProvider.overrideWith(StubProfileNotifier.new),
          equipmentOptionsProvider.overrideWith((ref) async => const []),
          injuryOptionsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: NavShell()),
      ),
    );

/// The vertical list inside [ExerciseListScreen] — as opposed to the
/// FilterBar's horizontal chip strip, which is also a [Scrollable] and would
/// otherwise make this finder ambiguous.
final _catalogueScrollable = find.descendant(
  of: find.byType(ExerciseListScreen),
  matching: find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

void main() {
  testWidgets(
      'keeps a tab mounted across a switch away and back, so its scroll '
      'position survives the trip', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const Key('nav.2')));
    await tester.pumpAndSettle();

    // IndexedStack in this Flutter version builds every child immediately on
    // mount (verified separately: all four tabs run initState the moment
    // NavShell first builds, not on first display), so a plain build-count
    // probe cannot discriminate "mounted lazily, then kept" from "mounted
    // eagerly, then torn down and rebuilt on every switch" — both start
    // counting from the same eager first build. Driving the real
    // ScrollPosition instead asserts the property IndexedStack actually
    // exists for: a tab's internal State (here, its ScrollController-backed
    // position) survives being hidden and shown again. jumpTo (not a drag)
    // keeps this independent of gesture/drag physics.
    final position = tester.state<ScrollableState>(_catalogueScrollable).position;
    position.jumpTo(400);
    await tester.pump();
    expect(position.pixels, 400, reason: 'the jump itself must have taken');

    await tester.tap(find.byKey(const Key('nav.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav.2')));
    await tester.pumpAndSettle();

    final positionAfterReturn =
        tester.state<ScrollableState>(_catalogueScrollable).position;
    expect(positionAfterReturn.pixels, 400,
        reason: 'IndexedStack must keep the tab mounted, not rebuild it');
  });

  testWidgets(
      'a tab never visited does not build at cold start, but a visited tab '
      'stays mounted (even offstage) after leaving it', (tester) async {
    await _pumpShell(tester);

    // find.byType defaults to skipOffstage: true, which for an IndexedStack
    // relies on its own debugVisitOnstageChildren override to reveal only
    // the *selected* child. That means a default finder reports findsNothing
    // for every non-current tab regardless of whether that tab was ever
    // built — both before and after this fix — so it cannot discriminate
    // "never mounted" from "mounted and sitting offstage". skipOffstage:
    // false walks the whole element tree instead, so it actually sees a tab
    // IndexedStack is hiding rather than one that was never built.
    expect(
      find.byType(PlanScreen, skipOffstage: false), findsNothing,
      reason: 'Train must not mount until the user visits it',
    );
    expect(
      find.byType(ExerciseListScreen, skipOffstage: false), findsNothing,
      reason: 'Browse must not mount until the user visits it',
    );
    expect(
      find.byType(SettingsScreen, skipOffstage: false), findsNothing,
      reason: 'Profile must not mount until the user visits it',
    );

    // Visit Browse, then leave it for Home. It must still be mounted (just
    // offstage), so the state-preservation IndexedStack exists for keeps
    // working — this half is also covered by the scroll-preservation test
    // above, but asserted here too since it is the other side of the same
    // change.
    await tester.tap(find.byKey(const Key('nav.2')));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseListScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav.0')));
    await tester.pumpAndSettle();
    expect(
      find.byType(ExerciseListScreen, skipOffstage: false), findsOneWidget,
      reason: 'once visited, Browse must stay mounted underneath (offstage), '
          'not be torn down when another tab is selected',
    );

    // Train and Profile remain unvisited throughout.
    expect(find.byType(PlanScreen, skipOffstage: false), findsNothing);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('tapping Train reaches the workout plan', (tester) async {
    // nav.0, nav.2 and nav.3 were already exercised above; nav.1 (Train) was
    // not, so nothing connected FsNav's index 1 to PlanScreen. home_screen_
    // test.dart proves onGoToTrain fires and nav_shell.dart wires it to
    // `_index = 1`, but nothing tied those two facts together — reordering
    // the tab list would send "Start workout" to the wrong screen with every
    // existing test still green. find.byType(PlanScreen) is discriminating
    // here because IndexedStack's debugVisitOnstageChildren override means a
    // default finder only ever sees the *selected* child — so this can only
    // be satisfied by PlanScreen actually being the current tab, not merely
    // present offstage somewhere in the tree.
    await _pumpShell(tester);

    await tester.tap(find.byKey(const Key('nav.1')));
    await tester.pumpAndSettle();

    expect(find.byType(PlanScreen), findsOneWidget);
  });

  testWidgets('tapping Browse reaches the exercise catalogue', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav.2')));
    await tester.pumpAndSettle();
    expect(find.text('Exercises'), findsOneWidget,
        reason: 'the Browse tab shows the catalogue, previously unreachable');
  });

  testWidgets('tapping Profile reaches account settings', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav.3')));
    await tester.pumpAndSettle();
    // byType, not text: SettingsScreen's own AppBar title is 'Profile', the
    // same word FsNav already uses as this tab's label, so a text finder
    // would be ambiguous between the label and the screen it opens onto.
    // The type is unique across the whole tree — nothing else in NavShell
    // is a SettingsScreen — so this cannot be satisfied by anything but the
    // real screen actually being current.
    expect(find.byType(SettingsScreen), findsOneWidget,
        reason: 'Profile must still reach Settings now that the gear icon '
            'plan_screen_test.dart tested is gone');
  });

  testWidgets("the swap sheet's equipment note lands on the Profile tab",
      (tester) async {
    // The one test that crosses all three files. The sheet's note, the
    // callback PlanScreen forwards and the index NavShell selects are each
    // covered on their own; only here does a wrong index in nav_shell.dart —
    // or a tab list reordered around it — actually show up as landing on the
    // wrong screen.
    await _pumpShell(tester, plan: _plan);

    await tester.tap(find.byKey(const Key('nav.1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('swap.open.601')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('swap.equipmentHint')));
    await tester.pumpAndSettle();

    // As above: IndexedStack only shows the selected child to a default
    // finder, so this holds only if Profile is genuinely the current tab.
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
