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
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

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

Future<void> _pumpShell(WidgetTester tester) => tester.pumpWidget(
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
          activePlanProvider.overrideWith((ref) async => null),
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

  testWidgets('reports the tapped tab as current', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav.2')));
    await tester.pumpAndSettle();
    expect(find.text('Exercises'), findsOneWidget,
        reason: 'the Browse tab shows the catalogue, previously unreachable');
  });
}
