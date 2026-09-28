import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/activity/data/step_permission.dart';
import 'package:fitsync/features/activity/domain/step_readings.dart';
import 'package:fitsync/features/activity/presentation/activity_sync.dart';
import 'package:fitsync/features/activity/presentation/providers.dart';

class _Permission implements StepPermission {
  _Permission(this.access);
  StepAccess access;
  int statusCalls = 0;

  @override
  Future<StepAccess> status() async {
    statusCalls++;
    return access;
  }

  @override
  Future<StepAccess> request() async => access;
  @override
  Future<void> openSettings() async {}
}

class _StubActivity extends ActivityController {
  int syncs = 0;

  @override
  Future<ActivityState> build() async => const ActivityState(
    today: DaySteps(steps: 0), week: null, offline: false,
  );
  @override
  Future<void> sync() async => syncs++;
}

Future<_StubActivity> _pump(WidgetTester tester, _Permission permission) async {
  final stub = _StubActivity();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      stepPermissionProvider.overrideWithValue(permission),
      activityProvider.overrideWith(() => stub),
    ],
    child: const MaterialApp(home: ActivitySync(child: SizedBox())),
  ));
  await tester.pumpAndSettle();
  return stub;
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('resume with counting on: re-reads the permission and syncs once', (tester) async {
    final permission = _Permission(StepAccess.granted);
    final stub = await _pump(tester, permission);
    expect(permission.statusCalls, 0);

    await _resume(tester);

    expect(permission.statusCalls, 1);
    expect(stub.syncs, 1);
  });

  for (final access in [StepAccess.notAsked, StepAccess.refused]) {
    testWidgets('resume with counting ${access.name}: no sync', (tester) async {
      final permission = _Permission(access);
      final stub = await _pump(tester, permission);

      await _resume(tester);

      expect(permission.statusCalls, 1);
      expect(stub.syncs, 0);
    });
  }

  testWidgets('turned on in Settings while away: the next resume syncs', (tester) async {
    final permission = _Permission(StepAccess.refused);
    final stub = await _pump(tester, permission);
    await _resume(tester);
    expect(stub.syncs, 0);

    permission.access = StepAccess.granted;
    await _resume(tester);

    expect(permission.statusCalls, 2);
    expect(stub.syncs, 1);
  });
}
