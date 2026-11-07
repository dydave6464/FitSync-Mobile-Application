import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/animations_tab.dart';
import 'package:fitsync/features/admin/presentation/exercise_preview_screen.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/widgets/admin_widgets.dart';

import 'helpers/fake_admin_repository.dart';

const _inUse = ApiException(
  'EXERCISE_IN_USE',
  "Trainees have this exercise in their plans or workouts, so it can't be "
      'unpublished.',
);

const _unclassifiable = ApiException(
  'EXERCISE_UNCLASSIFIABLE',
  "This exercise's safety rules couldn't be worked out, so it can't be "
      'published.',
);

AdminExercise _pending({String? reason = 'cardio'}) => sampleExercise(
  id: 41,
  name: 'romanian deadlift',
  muscleGroup: 'hamstrings',
  equipment: 'barbell',
  status: 'pending',
  pendingReason: reason,
);

AdminExercise _live() => sampleExercise(
  id: 41,
  name: 'romanian deadlift',
  muscleGroup: 'hamstrings',
  equipment: 'barbell',
);

/// The preview pushed over a page that keeps the Animations list alive, so
/// a test can see the list asked again.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdminRepository repo,
  AdminExercise exercise, {
  bool dark = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.listen(adminExercisesProvider, (_, _) {});
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExercisePreviewScreen(exercise: exercise),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shows the demo, name, muscle, equipment and why pending', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository(), _pending());

    expect(find.text('Romanian deadlift'), findsOneWidget);
    expect(find.text('Hamstrings'), findsOneWidget);
    expect(find.text('Barbell'), findsOneWidget);
    expect(find.text('Cardio exercise'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StatusTag),
        matching: find.text('Pending'),
      ),
      findsOneWidget,
    );
    final demo = tester.widget<Image>(
      find.byKey(const Key('admin.exercise.demo')),
    );
    expect(
      (demo.image as NetworkImage).url,
      'http://fitsync.test/storage/exercises/41/demo.gif',
    );
  });

  testWidgets('rare equipment is named as the reason', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(),
      _pending(reason: 'rare_equipment'),
    );

    expect(find.text('Uses rare equipment'), findsOneWidget);
    expect(find.text('Cardio exercise'), findsNothing);
  });

  testWidgets('a live demo gives no reason and offers Unpublish', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository(), _live());

    expect(find.text('Cardio exercise'), findsNothing);
    expect(find.text('Uses rare equipment'), findsNothing);
    expect(find.byKey(const Key('admin.exercise.publish')), findsNothing);
    expect(find.byKey(const Key('admin.exercise.unpublish')), findsOneWidget);
  });

  testWidgets('Publish puts it live and refreshes the list', (tester) async {
    final repo = FakeAdminRepository(
      publish: (id) async => sampleExercise(id: id, name: 'romanian deadlift'),
    );
    await _pump(tester, repo, _pending());
    final listCalls = repo.exercisesCalls.length;

    await tester.tap(find.byKey(const Key('admin.exercise.publish')));
    await tester.pumpAndSettle();

    expect(repo.publishCalls, [41]);
    expect(
      find.text('Published. Trainees can now find it in the exercise library.'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(StatusTag), matching: find.text('Live')),
      findsOneWidget,
    );
    expect(find.text('Cardio exercise'), findsNothing);
    expect(find.byKey(const Key('admin.exercise.unpublish')), findsOneWidget);
    expect(repo.exercisesCalls.length, greaterThan(listCalls));
  });

  testWidgets('a refused Publish says why and stays pending', (tester) async {
    final repo = FakeAdminRepository(
      publish: (_) async => throw _unclassifiable,
    );
    await _pump(tester, repo, _pending());

    await tester.tap(find.byKey(const Key('admin.exercise.publish')));
    await tester.pumpAndSettle();

    expect(find.text(_unclassifiable.message), findsOneWidget);
    expect(find.byKey(const Key('admin.exercise.publish')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StatusTag),
        matching: find.text('Pending'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Unpublish asks first; Keep leaves it live', (tester) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo, _live());

    await tester.tap(find.byKey(const Key('admin.exercise.unpublish')));
    await tester.pumpAndSettle();

    expect(find.text('Unpublish Romanian deadlift?'), findsOneWidget);
    expect(
      find.text(
        "It leaves the exercise library. Trainees can't get it in new plans.",
      ),
      findsOneWidget,
    );
    expect(find.text('Keep'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.unpublish.cancel')));
    await tester.pumpAndSettle();

    expect(repo.unpublishCalls, isEmpty);
    expect(find.byKey(const Key('admin.exercise.unpublish')), findsOneWidget);
  });

  testWidgets('a confirmed Unpublish sends it back to pending', (tester) async {
    final repo = FakeAdminRepository(
      unpublish: (id) async => sampleExercise(
        id: id,
        name: 'romanian deadlift',
        status: 'pending',
        pendingReason: 'rare_equipment',
      ),
    );
    await _pump(tester, repo, _live());
    final listCalls = repo.exercisesCalls.length;

    await tester.tap(find.byKey(const Key('admin.exercise.unpublish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.unpublish.confirm')));
    await tester.pumpAndSettle();

    expect(repo.unpublishCalls, [41]);
    expect(find.text('Unpublished.'), findsOneWidget);
    expect(find.byKey(const Key('admin.exercise.publish')), findsOneWidget);
    expect(find.text('Uses rare equipment'), findsOneWidget);
    expect(repo.exercisesCalls.length, greaterThan(listCalls));
  });

  testWidgets('an exercise in use is not unpublished, and says why', (
    tester,
  ) async {
    final repo = FakeAdminRepository(unpublish: (_) async => throw _inUse);
    await _pump(tester, repo, _live());

    await tester.tap(find.byKey(const Key('admin.exercise.unpublish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.unpublish.confirm')));
    await tester.pumpAndSettle();

    expect(find.text(_inUse.message), findsOneWidget);
    expect(find.byKey(const Key('admin.exercise.unpublish')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(StatusTag), matching: find.text('Live')),
      findsOneWidget,
    );
  });

  testWidgets('a row in the Animations list opens its preview', (tester) async {
    final container = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          FakeAdminRepository(
            exercises: (_, _, _) async => exercisesPage([_pending()]),
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
          home: const Scaffold(body: AnimationsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin.exercise.41')));
    await tester.pumpAndSettle();

    expect(find.byType(ExercisePreviewScreen), findsOneWidget);
    expect(find.text('Cardio exercise'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      FakeAdminRepository(),
      sampleExercise(
        name: 'barbell full squat with a very long descriptive name',
        muscleGroup: 'cardiovascular system',
        equipment: 'stationary bike',
        status: 'pending',
        pendingReason: 'rare_equipment',
      ),
      textScale: 2.0,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('admin.exercise.publish')),
      200,
      scrollable: find.byType(Scrollable).last,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(tester, FakeAdminRepository(), _pending(), dark: true);

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Romanian deadlift'))).brightness,
      Brightness.dark,
    );
  });
}
