import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show weightUnitProvider;
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/session_dates.dart';
import 'package:fitsync/features/sessions/domain/session_detail.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/session_detail_screen.dart';

/// A hand-picked chest and back workout, as the contract's example draws it.
const _detail = SessionDetail(
  sessionId: 41,
  sessionDate: '2026-11-04',
  setCount: 12,
  durationMin: 52,
  totalVolumeKg: 2953.5,
  muscleGroups: ['pectorals', 'pectorals', 'lats'],
  exercises: [
    SessionDetailExercise(
      exerciseId: 12,
      name: 'barbell bench press',
      muscleGroup: 'pectorals',
      equipment: 'Barbell',
      volumeKg: 1440,
      sets: [
        SessionDetailSet(setNumber: 1, weightKg: 60, reps: 8),
        SessionDetailSet(setNumber: 2, weightKg: 60, reps: 8),
        SessionDetailSet(setNumber: 3, weightKg: 60, reps: 8),
      ],
    ),
    SessionDetailExercise(
      exerciseId: 7,
      name: 'pull-up',
      muscleGroup: 'lats',
      equipment: 'body weight',
      sets: [
        SessionDetailSet(setNumber: 1, reps: 12),
        SessionDetailSet(setNumber: 2, weightKg: 10),
        SessionDetailSet(setNumber: 3),
      ],
    ),
  ],
);

class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository({this.value = _detail, this.error, this.gate});

  final SessionDetail value;
  Object? error;
  Completer<void>? gate;
  final asked = <int>[];

  @override
  Future<SessionDetail> detail(int sessionId) async {
    asked.add(sessionId);
    await gate?.future;
    if (error != null) throw error!;
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

Future<_FakeSessionRepository> _pump(
  WidgetTester tester, {
  _FakeSessionRepository? repo,
  WeightUnit unit = WeightUnit.kg,
  bool dark = false,
  String title = 'Chest & Back workout',
  bool settle = true,
}) async {
  final fake = repo ?? _FakeSessionRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(fake),
        weightUnitProvider.overrideWithValue(unit),
      ],
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        home: SessionDetailScreen(sessionId: 41, title: title),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('names the workout and the day it was trained', (tester) async {
    final fake = await _pump(tester);

    expect(fake.asked, [41]);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Chest & Back workout'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(sessionDayLabel('2026-11-04').toUpperCase()),
      findsOneWidget,
    );
    expect(find.text('12 sets · 2,954 kg · 52 min'), findsOneWidget);
  });

  testWidgets("shows the row's title at once, then the server's", (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(
      tester,
      repo: _FakeSessionRepository(
        gate: gate,
        value: const SessionDetail(
          sessionId: 41,
          sessionDate: '2026-11-04',
          setCount: 0,
          planName: 'Push Pull Legs',
          exercises: [],
        ),
      ),
      title: 'Old name',
      settle: false,
    );
    await tester.pump();

    expect(find.text('Old name'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.text('Old name'), findsNothing);
  });

  testWidgets('each exercise lists its sets', (tester) async {
    await _pump(tester);

    expect(find.text('Barbell bench press'), findsOneWidget);
    expect(find.text('Barbell'), findsOneWidget);
    expect(find.text('Set 1'), findsNWidgets(2));
    expect(find.text('60 kg × 8'), findsNWidgets(3));
    // The exercise's own volume, under its sets.
    expect(find.text('1,440 kg'), findsOneWidget);

    expect(find.text('Pull-up'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);
    expect(find.text('12 reps'), findsOneWidget);
    expect(find.text('10 kg'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a pound user reads pounds', (tester) async {
    await _pump(tester, unit: WeightUnit.lb);

    // 60 kg is 132.28 lb; formatWeight keeps one decimal for pounds.
    expect(find.text('132.3 lb × 8'), findsNWidgets(3));
    expect(find.text('60 kg × 8'), findsNothing);
    // 1,440 kg is 3,174.65 lb; 2,953.5 kg is 6,511.3 lb.
    expect(find.text('3,175 lb'), findsOneWidget);
    expect(find.text('12 sets · 6,511 lb · 52 min'), findsOneWidget);
  });

  testWidgets('a bodyweight workout leaves volume and missing time out', (
    tester,
  ) async {
    await _pump(
      tester,
      repo: _FakeSessionRepository(
        value: const SessionDetail(
          sessionId: 41,
          sessionDate: '2026-11-04',
          setCount: 1,
          totalVolumeKg: 0,
          exercises: [
            SessionDetailExercise(
              exerciseId: 7,
              name: 'pull-up',
              muscleGroup: 'lats',
              sets: [SessionDetailSet(setNumber: 1, reps: 12)],
            ),
          ],
        ),
      ),
    );

    expect(find.text('1 set'), findsOneWidget);
    expect(find.textContaining(' kg'), findsNothing);
  });

  testWidgets('a workout with no sets says so', (tester) async {
    await _pump(
      tester,
      repo: _FakeSessionRepository(
        value: const SessionDetail(
          sessionId: 41,
          sessionDate: '2026-11-04',
          setCount: 0,
          exercises: [],
        ),
      ),
    );

    expect(find.text('No sets were logged in this workout.'), findsOneWidget);
  });

  testWidgets('a workout that is gone says so, with nothing to retry', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      repo: _FakeSessionRepository(
        error: const ApiException('SESSION_NOT_FOUND', 'No such session.'),
      ),
      settle: false,
    );
    // One frame for the refused load to land: no retry backoff stands
    // between the refusal and the message.
    await tester.pump();

    expect(find.text("This workout isn't available any more."), findsOneWidget);
    expect(find.byType(FsRetry), findsNothing);
    expect(find.text('Try again'), findsNothing);

    // Asking again would only be refused again, so it is never asked again.
    await tester.pump(const Duration(minutes: 1));
    expect(fake.asked, [41]);
  });

  testWidgets('a failure that may pass is retried at most twice', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      repo: _FakeSessionRepository(
        error: const ApiException('NETWORK_ERROR', 'unreachable'),
      ),
      settle: false,
    );
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(fake.asked, [41, 41, 41]);
    expect(find.byType(FsRetry), findsOneWidget);
  });

  testWidgets('any other failure offers Try again, which reloads', (
    tester,
  ) async {
    final fake = _FakeSessionRepository(
      error: const ApiException('NETWORK_ERROR', 'unreachable'),
    );
    await _pump(tester, repo: fake);

    expect(find.byType(FsRetry), findsOneWidget);
    expect(
      find.text(userMessage(const ApiException('NETWORK_ERROR', ''))),
      findsOneWidget,
    );

    fake.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(fake.asked.length, greaterThan(1));
    expect(find.text('Barbell bench press'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'fits 360 x 640 at double text size (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _pump(tester, dark: dark, unit: WeightUnit.lb);
        expect(tester.takeException(), isNull);

        // Scrolled to the end, every row has been laid out at least once.
        await tester.drag(find.byType(ListView), const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Done'), findsOneWidget);
      },
    );
  }
}
