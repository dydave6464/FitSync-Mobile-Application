import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/manila_day.dart';
import 'package:fitsync/features/activity/data/step_permission.dart';
import 'package:fitsync/features/activity/data/step_source.dart';
import 'package:fitsync/features/activity/domain/step_readings.dart';
import 'package:fitsync/features/activity/presentation/activity_sync.dart';
import 'package:fitsync/features/activity/presentation/providers.dart';

/// The phone's live counter: one stream per start, so a test can push a
/// count into the stream started on a given day.
class _LiveSource implements StepSource {
  final starts = <DateTime>[];
  final streams = <StreamController<int>>[];

  @override
  Future<DaySteps> today(DateTime now) async => const DaySteps(steps: 0);
  @override
  Future<Map<String, int>> earlierDays(DateTime now) async => const {};
  @override
  Stream<int> live(DateTime now) {
    starts.add(now);
    final c = StreamController<int>();
    streams.add(c);
    return c.stream;
  }
}

class _Granted implements StepPermission {
  @override
  Future<StepAccess> status() async => StepAccess.granted;
  @override
  Future<StepAccess> request() async => StepAccess.granted;
  @override
  Future<void> openSettings() async {}
}

/// The saved count; a sync reads [next] (the new day's count).
class _Activity extends ActivityController {
  _Activity(this.steps);
  int steps;
  int? next;

  ActivityState _state() =>
      ActivityState(today: DaySteps(steps: steps), week: null, offline: false);

  @override
  Future<ActivityState> build() async => _state();
  @override
  Future<void> sync() async {
    if (next != null) steps = next!;
    state = AsyncData(_state());
  }
}

void main() {
  // 22:00 in Manila on Nov 5, then 08:00 on Nov 6.
  final evening = DateTime.utc(2026, 11, 5, 14);
  final nextMorning = DateTime.utc(2026, 11, 6, 0);

  test('a count reported after Manila midnight restarts the live stream '
      'on the new day instead of adding to yesterday', () async {
    var now = evening;
    final source = _LiveSource();
    final c = ProviderContainer(
      overrides: [
        stepSourceProvider.overrideWithValue(source),
        activityClockProvider.overrideWithValue(() => now),
        activityProvider.overrideWith(() => _Activity(300)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(stepsShownTodayProvider, (_, _) {});
    await pumpEventQueue();

    source.streams.single.add(9000);
    await pumpEventQueue();
    expect(c.read(stepsShownTodayProvider), 9000);

    // Overnight, yesterday's stream reports 500 more steps.
    now = nextMorning;
    source.streams.first.add(9500);
    await pumpEventQueue();

    expect(c.read(stepsShownTodayProvider), isNot(9500));
    expect(source.starts, hasLength(2));
    expect(manilaDayOf(source.starts.last), '2026-11-06');

    source.streams.last.add(500);
    await pumpEventQueue();
    expect(c.read(stepsShownTodayProvider), 500);
  });

  group('resume', () {
    late DateTime now;
    late _LiveSource source;
    late _Activity activity;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stepPermissionProvider.overrideWithValue(_Granted()),
            stepSourceProvider.overrideWithValue(source),
            activityClockProvider.overrideWithValue(() => now),
            activityProvider.overrideWith(() => activity),
          ],
          child: MaterialApp(
            home: ActivitySync(
              child: Consumer(
                builder: (context, ref, _) =>
                    Text('steps ${ref.watch(stepsShownTodayProvider)}'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      source.streams.single.add(9000);
      await tester.pumpAndSettle();
      expect(find.text('steps 9000'), findsOneWidget);
    }

    Future<void> resume(WidgetTester tester) async {
      final b = tester.binding;
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    setUp(() {
      now = evening;
      source = _LiveSource();
      activity = _Activity(9000);
    });

    testWidgets('on a new Manila day drops yesterday\'s live count and '
        'restarts the stream from the new midnight', (tester) async {
      await pump(tester);

      now = nextMorning;
      activity.next = 40;
      await resume(tester);

      expect(find.text('steps 9000'), findsNothing);
      expect(find.text('steps 40'), findsOneWidget);
      expect(source.starts, hasLength(2));
      expect(manilaDayOf(source.starts.last), '2026-11-06');
    });

    testWidgets('later the same Manila day keeps the running stream', (
      tester,
    ) async {
      await pump(tester);

      now = evening.add(const Duration(hours: 1));
      await resume(tester);

      expect(find.text('steps 9000'), findsOneWidget);
      expect(source.starts, hasLength(1));
    });
  });
}
