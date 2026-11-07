import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/animations_tab.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/widgets/admin_widgets.dart';

import 'helpers/fake_admin_repository.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  bool dark = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
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
        home: const Scaffold(body: AnimationsTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// [count] exercises, ids counting up from 100 + [from].
List<AdminExercise> _rows(int count, {int from = 0, String status = 'live'}) =>
    [
      for (var i = from; i < from + count; i++)
        sampleExercise(id: 100 + i, name: 'exercise $i', status: status),
    ];

/// A server of [total] exercises in pages of 30.
FakeAdminRepository _paged(int total) => FakeAdminRepository(
  exercises: (status, q, page) async {
    final start = (page - 1) * 30;
    final count = (total - start).clamp(0, 30);
    return exercisesPage(
      _rows(count, from: start),
      page: page,
      total: total,
    );
  },
);

Text _tagText(WidgetTester tester, String row, String tag) => tester.widget(
  find.descendant(
    of: find.byKey(ValueKey(row)),
    matching: find.descendant(
      of: find.byType(StatusTag),
      matching: find.text(tag),
    ),
  ),
);

void main() {
  testWidgets('asks for the pending demos first, with both counts', (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      exercises: (_, _, _) async =>
          exercisesPage(_rows(2, status: 'pending'), pending: 121, live: 1203),
    );
    await _pump(tester, repo);

    expect(repo.exercisesCalls, [(status: 'pending', q: '', page: 1)]);
    expect(find.text('Pending (121)'), findsOneWidget);
    expect(find.text('Live (1,203)'), findsOneWidget);
    expect(find.text('Search exercises'), findsOneWidget);
  });

  testWidgets('a row shows the name, muscle, equipment and status', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      FakeAdminRepository(
        exercises: (_, _, _) async => exercisesPage([
          sampleExercise(
            id: 41,
            name: 'romanian deadlift',
            muscleGroup: 'hamstrings',
            equipment: 'barbell',
            status: 'pending',
          ),
          sampleExercise(
            id: 42,
            name: 'incline press',
            muscleGroup: 'pectorals',
            equipment: 'dumbbell',
          ),
        ]),
      ),
    );

    expect(find.text('Romanian deadlift'), findsOneWidget);
    expect(find.text('Hamstrings · Barbell'), findsOneWidget);
    expect(find.text('Chest · Dumbbells'), findsOneWidget);

    final t = FsTokens.light;
    // Amber as a dot beside the word: amber text is 2.5:1 on the light
    // theme's tag, too faint to read, so the word keeps the tag's own grey.
    expect(
      _tagText(tester, 'admin.exercise.41', 'Pending').style?.color,
      t.text2,
    );
    final pendingTag = tester.widget<StatusTag>(
      find.descendant(
        of: find.byKey(const ValueKey('admin.exercise.41')),
        matching: find.byType(StatusTag),
      ),
    );
    expect(pendingTag.dot, t.amber);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin.exercise.41')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration! as BoxDecoration).color == t.amber,
        ),
      ),
      findsOneWidget,
    );
    expect(
      _tagText(tester, 'admin.exercise.42', 'Live').style?.color,
      t.accentText,
    );
    // Read as one line, the status in words.
    expect(
      find.bySemanticsLabel('Romanian deadlift, Hamstrings · Barbell, Pending'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the row thumbnail joins the server address', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        exercises: (_, _, _) async => exercisesPage([
          sampleExercise(thumbnailUrl: '/storage/exercises/41/thumb.jpg'),
        ]),
      ),
    );

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('admin.exercise.41')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (image.image as NetworkImage).url,
      'http://fitsync.test/storage/exercises/41/thumb.jpg',
    );
  });

  testWidgets('the Live chip asks for live demos', (tester) async {
    final repo = FakeAdminRepository(
      exercises: (_, _, _) async => exercisesPage(_rows(2)),
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Live (1,203)'));
    await tester.pumpAndSettle();

    expect(repo.exercisesCalls.last, (status: 'live', q: '', page: 1));
  });

  testWidgets('typing searches once, 300 ms after the last key', (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      exercises: (_, _, _) async => exercisesPage(_rows(2)),
    );
    await _pump(tester, repo);

    final field = find.byKey(const Key('admin.exercises.search'));
    for (final text in ['d', 'de', 'dea']) {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repo.exercisesCalls, hasLength(1), reason: 'still typing');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repo.exercisesCalls.last, (status: 'pending', q: 'dea', page: 1));
  });

  testWidgets('scrolling near the end loads the next page', (tester) async {
    final repo = _paged(45);
    await _pump(tester, repo);

    await tester.scrollUntilVisible(
      find.text('Exercise 29'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(repo.exercisesCalls.map((c) => c.page), [1, 2]);

    await tester.scrollUntilVisible(
      find.text('Exercise 44'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(repo.exercisesCalls.map((c) => c.page), [1, 2]);
  });

  testWidgets('a failed next page keeps the list and says why', (tester) async {
    final repo = FakeAdminRepository(
      exercises: (_, _, page) async {
        if (page > 1) throw refused;
        return exercisesPage(_rows(30), total: 40);
      },
    );
    await _pump(tester, repo);

    await tester.scrollUntilVisible(
      find.text('Exercise 29'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('The server said no.'), findsOneWidget);
    expect(find.text('Exercise 29'), findsOneWidget);
  });

  // As the Users tab: one failure, one request, until Try again.
  testWidgets('a failed next page is asked once, then offers Try again', (
    tester,
  ) async {
    var fail = true;
    final repo = FakeAdminRepository(
      exercises: (_, _, page) async {
        if (page > 1) {
          if (fail) throw refused;
          return exercisesPage(_rows(10, from: 30), page: 2, total: 40);
        }
        return exercisesPage(_rows(30), total: 40);
      },
    );
    await _pump(tester, repo);

    await tester.scrollUntilVisible(
      find.text('Exercise 29'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 100));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await tester.pumpAndSettle();
    }

    expect(repo.exercisesCalls.map((c) => c.page), [1, 2]);
    expect(find.text('The server said no.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    fail = false;
    await tester.tap(find.byKey(const Key('admin.exercises.more.retry')));
    await tester.pumpAndSettle();

    expect(repo.exercisesCalls.map((c) => c.page), [1, 2, 2]);
    expect(find.text('The server said no.'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Exercise 39'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Exercise 39'), findsOneWidget);
  });

  testWidgets('nothing pending says so', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        exercises: (_, _, _) async => exercisesPage(const [], pending: 0),
      ),
    );

    expect(find.text('Nothing waiting for review.'), findsOneWidget);
  });

  testWidgets('a search with no match offers Clear search', (tester) async {
    final repo = FakeAdminRepository(
      exercises: (_, q, _) async =>
          q.isEmpty ? exercisesPage(_rows(2)) : exercisesPage(const []),
    );
    await _pump(tester, repo);

    await tester.enterText(
      find.byKey(const Key('admin.exercises.search')),
      'zzz',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('No exercises match "zzz".'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.exercises.clear')));
    await tester.pumpAndSettle();

    expect(repo.exercisesCalls.last, (status: 'pending', q: '', page: 1));
    expect(find.text('Exercise 0'), findsOneWidget);
  });

  testWidgets('a failed load offers Try again', (tester) async {
    var fail = true;
    final repo = FakeAdminRepository(
      exercises: (_, _, _) async {
        if (fail) throw refused;
        return exercisesPage(_rows(1));
      },
    );
    await _pump(tester, repo);

    expect(find.text('The server said no.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('admin.exercises.retry')));
    await tester.pumpAndSettle();

    expect(find.text('Exercise 0'), findsOneWidget);
  });

  testWidgets('chips keep their counts while a new list loads', (tester) async {
    final second = Completer<AdminExercisesPage>();
    var calls = 0;
    await _pump(
      tester,
      FakeAdminRepository(
        exercises: (_, _, _) {
          calls++;
          return calls == 1
              ? Future.value(exercisesPage(_rows(1)))
              : second.future;
        },
      ),
    );

    await tester.tap(find.text('Live (1,203)'));
    await tester.pump();

    expect(find.text('Live (1,203)'), findsOneWidget);
    expect(find.text('Pending (121)'), findsOneWidget);
    second.complete(exercisesPage(_rows(1)));
    await tester.pumpAndSettle();
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      FakeAdminRepository(
        exercises: (_, _, _) async => exercisesPage([
          sampleExercise(
            name: 'barbell full squat with a very long descriptive name',
            muscleGroup: 'cardiovascular system',
            equipment: 'stationary bike',
            status: 'pending',
          ),
          ..._rows(4),
        ]),
      ),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        exercises: (_, _, _) async => exercisesPage(_rows(2)),
      ),
      dark: true,
    );

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Exercise 0'))).brightness,
      Brightness.dark,
    );
  });
}
