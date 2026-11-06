import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/profile/presentation/widgets/weigh_ins_sheet.dart';

const _profile = Profile(
  userId: 1,
  email: 'a@b.c',
  fullName: 'A',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: [],
  injuries: [],
);

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.deleteError});

  /// Thrown by [deleteBodyWeight] instead of deleting, when set.
  Object? deleteError;

  /// Completes [deleteBodyWeight] when set, so a test can look mid-delete.
  Completer<void>? gate;

  final deleted = <String>[];
  int loads = 0;

  @override
  Future<Profile> load() async {
    loads += 1;
    return _profile;
  }

  @override
  Future<void> deleteBodyWeight(String loggedOn) async {
    if (gate != null) await gate!.future;
    if (deleteError != null) throw deleteError!;
    deleted.add(loggedOn);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Noon on 6 Nov 2026 in Manila.
final _noonNov6 = DateTime.utc(2026, 11, 6, 4);

/// Oldest first, as the server sends them.
const _three = [
  BodyWeightPoint(loggedOn: '2026-11-02', weightKg: 73),
  BodyWeightPoint(loggedOn: '2026-11-04', weightKg: 72.5),
  BodyWeightPoint(loggedOn: '2026-11-06', weightKg: 72),
];

class _Fetches {
  final periods = <String>[];
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeProfileRepository repo,
  List<BodyWeightPoint> points = _three,
  WeightUnit unit = WeightUnit.kg,
  _Fetches? fetches,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bodyWeightClockProvider.overrideWithValue(() => _noonNov6),
        profileRepositoryProvider.overrideWithValue(repo),
        weightUnitProvider.overrideWithValue(unit),
        bodyWeightProvider.overrideWith((ref, period) async {
          fetches?.periods.add(period);
          return BodyWeightSeries(
            widened: false,
            points: points,
            reference: null,
            unit: 'kg',
            entries: points.length,
          );
        }),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // As the Profile screen does: something holds profileProvider,
              // so an invalidate refetches it.
              ref.watch(profileProvider);
              return ElevatedButton(
                onPressed: () => showWeighInsSheet(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _deleteButton(String loggedOn) =>
    find.byKey(Key('weighIns.delete.$loggedOn'));

void main() {
  testWidgets('lists the weigh-ins newest first, in the user\'s unit', (
    tester,
  ) async {
    final fetches = _Fetches();
    await _pump(
      tester,
      repo: _FakeProfileRepository(),
      unit: WeightUnit.lb,
      fetches: fetches,
    );

    expect(find.text('Your weigh-ins'), findsOneWidget);
    expect(fetches.periods, contains('year'));

    final today = tester.getTopLeft(find.text('Today')).dy;
    final nov4 = tester.getTopLeft(find.text('Wed, Nov 4')).dy;
    final nov2 = tester.getTopLeft(find.text('Mon, Nov 2')).dy;
    expect(today, lessThan(nov4));
    expect(nov4, lessThan(nov2));

    // 72.5 kg is 159.8 lb.
    expect(find.text('159.8 lb'), findsOneWidget);
    expect(find.text('72.5 kg'), findsNothing);
  });

  testWidgets('each delete button is 48 dp and named for its day', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _FakeProfileRepository());

    final button = _deleteButton('2026-11-04');
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(find.byTooltip('Delete weigh-in for Wed, Nov 4'), findsOneWidget);
    expect(
      tester.getSemantics(button),
      matchesSemantics(
        tooltip: 'Delete weigh-in for Wed, Nov 4',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('delete asks first, with the exact title and message', (
    tester,
  ) async {
    await _pump(tester, repo: _FakeProfileRepository());

    await tester.tap(_deleteButton('2026-11-04'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this weigh-in?'), findsOneWidget);
    expect(
      find.text('72.5 kg on Wed, Nov 4 comes off your chart.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('weighIn.delete.cancel')), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Keep deletes nothing', (tester) async {
    final repo = _FakeProfileRepository();
    await _pump(tester, repo: repo);

    await tester.tap(_deleteButton('2026-11-04'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weighIn.delete.cancel')));
    await tester.pumpAndSettle();

    expect(repo.deleted, isEmpty);
    expect(find.text('Your weigh-ins'), findsOneWidget);
    expect(find.text('Weigh-in deleted'), findsNothing);
  });

  testWidgets(
    'Delete removes it, refreshes the chart and profile, and says so',
    (tester) async {
      final repo = _FakeProfileRepository();
      final fetches = _Fetches();
      await _pump(tester, repo: repo, fetches: fetches);
      final loadsBefore = repo.loads;
      final fetchesBefore = fetches.periods.length;

      await tester.tap(_deleteButton('2026-11-04'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weighIn.delete.confirm')));
      await tester.pumpAndSettle();

      expect(repo.deleted, ['2026-11-04']);
      expect(find.text('Weigh-in deleted'), findsOneWidget);
      expect(repo.loads, greaterThan(loadsBefore));
      expect(fetches.periods.length, greaterThan(fetchesBefore));
    },
  );

  testWidgets('deleting the newest names the weight it goes back to', (
    tester,
  ) async {
    await _pump(tester, repo: _FakeProfileRepository());

    await tester.tap(_deleteButton('2026-11-06'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '72 kg on Fri, Nov 6 comes off your chart. '
        'Your weight goes back to 72.5 kg, from Wed, Nov 4.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a single weigh-in shows how to fix it, and no delete', (
    tester,
  ) async {
    await _pump(
      tester,
      repo: _FakeProfileRepository(),
      points: const [BodyWeightPoint(loggedOn: '2026-11-04', weightKg: 72.5)],
    );

    expect(
      find.text(
        'To fix your only weigh-in, log the right weight for that day. '
        'It replaces the old one.',
      ),
      findsOneWidget,
    );
    expect(_deleteButton('2026-11-04'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('one already deleted elsewhere is said plainly', (tester) async {
    final repo = _FakeProfileRepository(
      deleteError: const ApiException(
        'WEIGH_IN_NOT_FOUND',
        "There's no weigh-in on that day.",
      ),
    );
    final fetches = _Fetches();
    await _pump(tester, repo: repo, fetches: fetches);
    final fetchesBefore = fetches.periods.length;

    await tester.tap(_deleteButton('2026-11-04'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weighIn.delete.confirm')));
    await tester.pumpAndSettle();

    expect(find.text('That weigh-in was already deleted.'), findsOneWidget);
    expect(find.text("There's no weigh-in on that day."), findsNothing);
    expect(fetches.periods.length, greaterThan(fetchesBefore));
  });

  testWidgets('any other failure shows the server\'s message', (tester) async {
    const message =
        "You can't delete your only weigh-in. To fix it, log the right "
        'weight for that day. It replaces this one.';
    final repo = _FakeProfileRepository(
      deleteError: const ApiException('ONLY_WEIGH_IN', message),
    );
    await _pump(tester, repo: repo);

    await tester.tap(_deleteButton('2026-11-04'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weighIn.delete.confirm')));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.text('Weigh-in deleted'), findsNothing);
    // The delete can be tried again.
    final button = tester.widget<IconButton>(_deleteButton('2026-11-04'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('while one deletes, its button is busy and the rest wait', (
    tester,
  ) async {
    final repo = _FakeProfileRepository()..gate = Completer<void>();
    await _pump(tester, repo: repo);

    await tester.tap(_deleteButton('2026-11-04'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weighIn.delete.confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    IconButton buttonOf(String day) =>
        tester.widget<IconButton>(_deleteButton(day));
    expect(
      find.descendant(
        of: _deleteButton('2026-11-04'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(buttonOf('2026-11-04').onPressed, isNull);
    expect(buttonOf('2026-11-06').onPressed, isNull);
    expect(buttonOf('2026-11-02').onPressed, isNull);

    repo.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('fits a 320 dp screen at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, repo: _FakeProfileRepository());

    expect(tester.takeException(), isNull);
    expect(find.text('Your weigh-ins'), findsOneWidget);
  });
}
