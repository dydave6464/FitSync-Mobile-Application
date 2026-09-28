import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/activity/domain/activity.dart';
import 'package:fitsync/features/activity/domain/step_readings.dart';
import 'package:fitsync/features/activity/presentation/activity_screen.dart';
import 'package:fitsync/features/activity/presentation/providers.dart';

ActivityDay _d(int day, int? steps) => ActivityDay(
  date: '2026-09-${day.toString().padLeft(2, '0')}', steps: steps,
  caloriesBurned: steps == null ? null : 158, distanceKm: steps == null ? null : 4.52,
  activeMinutes: steps == null ? null : 64,
);

ActivityWeek _week({int? usual = 5180, List<String> missing = const []}) => ActivityWeek(
  days: [_d(22, 3000), _d(23, null), _d(24, 5000), _d(25, 6000), _d(26, null), _d(27, 4000), _d(28, 6420)],
  usual: usual,
  missing: missing,
);

class _StubActivity extends ActivityController {
  _StubActivity(this.value);
  final ActivityState value;
  int syncs = 0;

  @override
  Future<ActivityState> build() async => value;
  @override
  Future<void> sync() async => syncs++;
}

Future<_StubActivity> _pump(
  WidgetTester tester,
  ActivityState state, {
  ActivityScreen screen = const ActivityScreen(),
}) async {
  final stub = _StubActivity(state);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      activityProvider.overrideWith(() => stub),
      liveStepsProvider.overrideWith((ref) => const Stream<int>.empty()),
    ],
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
  return stub;
}

class _RetrySyncCount {
  int calls = 0;
}

/// First build fails, like a real server error; the next one (after "Try
/// again" invalidates the provider) succeeds. `sync()` mirrors the real
/// [ActivityController.sync]'s first line -- reading `state.value` -- the
/// call that throws `UnmountedRefException` if it ever runs against a
/// disposed instance.
class _RetryStub extends ActivityController {
  _RetryStub(this.calls);
  final _RetrySyncCount calls;
  int attempt = 0;

  @override
  Future<ActivityState> build() async {
    if (attempt++ == 0) throw const ApiException('SERVER_ERROR', 'broke');
    return ActivityState(today: const DaySteps(steps: 6420), week: _week(), offline: false);
  }

  @override
  Future<void> sync() async {
    state.value;
    calls.calls++;
  }
}

void main() {
  testWidgets('shows today against the usual, the estimates and the week', (tester) async {
    await _pump(tester, ActivityState(
      today: const DaySteps(steps: 6420), week: _week(), offline: false,
    ));

    expect(find.text('6,420'), findsOneWidget);
    expect(find.text('steps today'), findsOneWidget);
    expect(find.text('1,240 above your usual'), findsOneWidget);
    // The usual is marked with a ▲ under the bar.
    expect(
      find.descendant(
        of: find.byKey(const Key('activity.usualMarker')),
        matching: find.byIcon(Icons.arrow_drop_up),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: find.byKey(const Key('activity.kcal')), matching: find.text('158')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('activity.km')), matching: find.text('4.52')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('activity.minutes')), matching: find.text('64')), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    // (3000 + 5000 + 6000 + 4000 + 6420) / 5 = 4884
    expect(find.text('avg 4.9k/day'), findsOneWidget);
  });

  testWidgets('before three days there is no usual and no marker yet', (tester) async {
    await _pump(tester, ActivityState(
      today: const DaySteps(steps: 6420), week: _week(usual: null), offline: false,
    ));

    expect(find.text('Your usual appears after 3 days of walking'), findsOneWidget);
    expect(find.byKey(const Key('activity.usualMarker')), findsNothing);
  });

  testWidgets('missing height shows dashes and a way to Profile', (tester) async {
    await _pump(tester, ActivityState(
      today: const DaySteps(steps: 6420), week: _week(missing: ['height']), offline: false,
    ));

    expect(find.descendant(of: find.byKey(const Key('activity.kcal')), matching: find.text('—')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('activity.km')), matching: find.text('—')), findsOneWidget);
    expect(find.text('Add your height and weight in Profile'), findsOneWidget);
  });

  testWidgets('Android notes and offline note appear when they apply', (tester) async {
    await _pump(tester, ActivityState(
      today: const DaySteps(steps: 300, sinceTurnedOn: true, includesEarlierDays: true),
      week: _week(), offline: true,
    ));

    expect(find.text('Counting since you turned it on'), findsOneWidget);
    expect(find.text("Steps from days FitSync wasn't opened are added to the next day"), findsOneWidget);
    expect(find.text("Updates when you're online"), findsOneWidget);
  });

  testWidgets('never reached the server: steps, no week', (tester) async {
    await _pump(tester, const ActivityState(
      today: DaySteps(steps: 300), week: null, offline: true,
    ));

    expect(find.text('300'), findsOneWidget);
    expect(find.text('This week'), findsNothing);
  });

  testWidgets('leaving the screen syncs', (tester) async {
    final stub = await _pump(tester, ActivityState(
      today: const DaySteps(steps: 6420), week: _week(), offline: false,
    ));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(stub.syncs, 1);
  });

  testWidgets('while open, syncs every syncEvery', (tester) async {
    final stub = await _pump(
      tester,
      ActivityState(today: const DaySteps(steps: 6420), week: _week(), offline: false),
      screen: const ActivityScreen(syncEvery: Duration(seconds: 1)),
    );
    expect(stub.syncs, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(stub.syncs, 2);
  });

  testWidgets('a retry after an error keeps syncing correctly', (tester) async {
    final calls = _RetrySyncCount();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activityProvider.overrideWith(() => _RetryStub(calls)),
        liveStepsProvider.overrideWith((ref) => const Stream<int>.empty()),
      ],
      child: const MaterialApp(home: ActivityScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('broke'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('6,420'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(calls.calls, 1);
  });
}
