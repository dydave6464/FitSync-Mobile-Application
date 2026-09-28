import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/activity/data/step_permission.dart';
import 'package:fitsync/features/activity/data/step_source.dart';
import 'package:fitsync/features/activity/domain/step_readings.dart';
import 'package:fitsync/features/activity/presentation/activation_screen.dart';
import 'package:fitsync/features/activity/presentation/activity_screen.dart';
import 'package:fitsync/features/activity/presentation/providers.dart';

class _FakePermission implements StepPermission {
  _FakePermission(this.answer);
  final StepAccess answer;
  int requests = 0;

  @override
  Future<StepAccess> status() async => StepAccess.notAsked;
  @override
  Future<StepAccess> request() async {
    requests++;
    return answer;
  }
  @override
  Future<void> openSettings() async {}
}

class _StubActivity extends ActivityController {
  @override
  Future<ActivityState> build() async =>
      const ActivityState(today: DaySteps(steps: 0), week: null, offline: false);
  @override
  Future<void> sync() async {}
}

Future<void> _pump(WidgetTester tester, _FakePermission permission) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      stepPermissionProvider.overrideWithValue(permission),
      stepSourceProvider.overrideWithValue(const NoStepSource()),
      activityProvider.overrideWith(_StubActivity.new),
      liveStepsProvider.overrideWith((ref) => const Stream<int>.empty()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ActivationScreen()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explains the feature before asking', (tester) async {
    await _pump(tester, _FakePermission(StepAccess.granted));

    expect(find.text('FitSync counts your steps all day, automatically.'), findsOneWidget);
    expect(find.textContaining('no watch needed'), findsOneWidget);
    expect(find.text('Works without internet'), findsOneWidget);
    expect(find.text('Only daily totals are saved to your account'), findsOneWidget);
  });

  testWidgets('Start asks the phone and, when allowed, opens Activity', (tester) async {
    final permission = _FakePermission(StepAccess.granted);
    await _pump(tester, permission);

    await tester.tap(find.byKey(const Key('activity.start')));
    await tester.pumpAndSettle();

    expect(permission.requests, 1);
    expect(find.byType(ActivationScreen), findsNothing);
    expect(find.byType(ActivityScreen), findsOneWidget);
  });

  testWidgets('Start refused goes back without opening Activity', (tester) async {
    final permission = _FakePermission(StepAccess.refused);
    await _pump(tester, permission);

    await tester.tap(find.byKey(const Key('activity.start')));
    await tester.pumpAndSettle();

    expect(permission.requests, 1);
    expect(find.byType(ActivationScreen), findsNothing);
    expect(find.byType(ActivityScreen), findsNothing);
  });

  testWidgets('Not now goes back without asking the phone', (tester) async {
    final permission = _FakePermission(StepAccess.granted);
    await _pump(tester, permission);

    await tester.tap(find.byKey(const Key('activity.notNow')));
    await tester.pumpAndSettle();

    expect(permission.requests, 0);
    expect(find.byType(ActivationScreen), findsNothing);
  });
}
