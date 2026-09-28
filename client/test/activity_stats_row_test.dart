import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/activity/data/step_permission.dart';
import 'package:fitsync/features/activity/domain/activity.dart';
import 'package:fitsync/features/activity/domain/step_readings.dart';
import 'package:fitsync/features/activity/presentation/activation_screen.dart';
import 'package:fitsync/features/activity/presentation/activity_screen.dart';
import 'package:fitsync/features/activity/presentation/providers.dart';
import 'package:fitsync/features/activity/presentation/widgets/activity_stats_row.dart';

class _Permission implements StepPermission {
  _Permission(this.access, {this.onRequest});
  StepAccess access;
  final StepAccess? onRequest;
  final log = <String>[];

  @override
  Future<StepAccess> status() async => access;
  @override
  Future<StepAccess> request() async {
    log.add('request');
    return access = onRequest ?? access;
  }
  @override
  Future<void> openSettings() async => log.add('settings');
}

class _StubActivity extends ActivityController {
  _StubActivity(this.value);
  final ActivityState value;
  @override
  Future<ActivityState> build() async => value;
  @override
  Future<void> sync() async {}
}

ActivityWeek _week({List<String> missing = const []}) => ActivityWeek(
  days: [
    for (var d = 22; d <= 28; d++)
      ActivityDay(date: '2026-09-$d', steps: d == 28 ? 6420 : null,
        caloriesBurned: d == 28 ? 158 : null, distanceKm: d == 28 ? 4.52 : null,
        activeMinutes: d == 28 ? 64 : null),
  ],
  usual: null,
  missing: missing,
);

Future<void> _pump(WidgetTester tester, _Permission permission, {ActivityWeek? week}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      stepPermissionProvider.overrideWithValue(permission),
      activityProvider.overrideWith(() => _StubActivity(ActivityState(
        today: const DaySteps(steps: 6420), week: week ?? _week(), offline: false,
      ))),
      liveStepsProvider.overrideWith((ref) => const Stream<int>.empty()),
    ],
    child: const MaterialApp(home: Scaffold(body: ActivityStatsRow())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  Finder tile(String key, String value) => find.descendant(
    of: find.byKey(Key('home.activity.$key')),
    matching: find.text(value),
  );

  testWidgets('not turned on: three zero tiles, any of them opens the activation screen', (tester) async {
    await _pump(tester, _Permission(StepAccess.notAsked));

    expect(tile('steps', '0'), findsOneWidget);
    expect(tile('kcal', '0'), findsOneWidget);
    expect(tile('km', '0.0'), findsOneWidget);
    expect(find.text('Tap to start counting your steps'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.activity.kcal')));
    await tester.pumpAndSettle();
    expect(find.byType(ActivationScreen), findsOneWidget);
  });

  testWidgets('refused: zero tiles; a tap asks again, then opens Settings if still refused', (tester) async {
    final permission = _Permission(StepAccess.refused);
    await _pump(tester, permission);

    expect(tile('steps', '0'), findsOneWidget);
    expect(find.text('Step counting is off — tap to allow'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.activity.steps')));
    await tester.pumpAndSettle();
    expect(permission.log, ['request', 'settings']);
  });

  testWidgets('refused, granted when asked again: no Settings, the stats show', (tester) async {
    final permission = _Permission(StepAccess.refused, onRequest: StepAccess.granted);
    await _pump(tester, permission);

    expect(find.text('Step counting is off — tap to allow'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.activity.km')));
    await tester.pumpAndSettle();
    expect(permission.log, ['request']);
    expect(tile('steps', '6,420'), findsOneWidget);
    expect(find.text('Step counting is off — tap to allow'), findsNothing);
  });

  testWidgets('while step access loads: zero tiles that do nothing when tapped', (tester) async {
    final pending = Completer<StepAccess>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stepPermissionProvider.overrideWithValue(_PendingPermission(pending.future)),
      ],
      child: const MaterialApp(home: Scaffold(body: ActivityStatsRow())),
    ));
    await tester.pump();

    expect(tile('steps', '0'), findsOneWidget);
    expect(tile('kcal', '0'), findsOneWidget);
    expect(tile('km', '0.0'), findsOneWidget);
    expect(find.text('Tap to start counting your steps'), findsNothing);
    await tester.tap(find.byKey(const Key('home.activity.steps')));
    await tester.pump();
    expect(find.byType(ActivationScreen), findsNothing);

    pending.complete(StepAccess.notAsked);
    await tester.pumpAndSettle();
    expect(find.text('Tap to start counting your steps'), findsOneWidget);
  });

  testWidgets('on: steps, kcal and km, each opening Activity', (tester) async {
    await _pump(tester, _Permission(StepAccess.granted));

    expect(find.descendant(of: find.byKey(const Key('home.activity.steps')), matching: find.text('6,420')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('home.activity.kcal')), matching: find.text('158')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('home.activity.km')), matching: find.text('4.5')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.activity.km')));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
  });

  testWidgets('on, weight missing: kcal is a dash, km stays', (tester) async {
    await _pump(tester, _Permission(StepAccess.granted), week: _week(missing: ['weight']));

    expect(find.descendant(of: find.byKey(const Key('home.activity.kcal')), matching: find.text('—')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('home.activity.km')), matching: find.text('4.5')), findsOneWidget);
  });
}

/// A permission whose status has not answered yet.
class _PendingPermission implements StepPermission {
  _PendingPermission(this._status);
  final Future<StepAccess> _status;

  @override
  Future<StepAccess> status() => _status;
  @override
  Future<StepAccess> request() async => StepAccess.refused;
  @override
  Future<void> openSettings() async {}
}
