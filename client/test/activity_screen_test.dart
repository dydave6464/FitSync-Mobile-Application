import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/activity/domain/activity.dart';
import 'package:fitsync/features/activity/domain/step_readings.dart';
import 'package:fitsync/features/activity/presentation/activity_screen.dart';
import 'package:fitsync/features/activity/presentation/providers.dart';

import 'helpers/a11y.dart' show contrast;

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
  bool dark = false,
}) async {
  final stub = _StubActivity(state);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      activityProvider.overrideWith(() => stub),
      liveStepsProvider.overrideWith((ref) => const Stream<int>.empty()),
    ],
    child: MaterialApp(theme: dark ? fsDarkTheme() : fsLightTheme(), home: screen),
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

  for (final dark in [false, true]) {
    testWidgets('every day of the week reads against its card (${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(
        tester,
        ActivityState(today: const DaySteps(steps: 6420), week: _week(), offline: false),
        dark: dark,
      );

      final t = (dark ? fsDarkTheme() : fsLightTheme()).extension<FsTokens>()!;
      final chart = tester.widget<BarChart>(
        find.descendant(of: find.byKey(const Key('activity.week')), matching: find.byType(BarChart)),
      );
      final rods = [for (final g in chart.data.barGroups) ...g.barRods];
      expect(rods, hasLength(7));
      for (final rod in rods) {
        // WCAG 1.4.11: a bar is a graphical object and needs 3:1.
        expect(contrast(rod.color!, t.surface), greaterThanOrEqualTo(3));
      }
    });
  }

  testWidgets('the week chart reads each day out to a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, ActivityState(today: const DaySteps(steps: 6500), week: _week(), offline: false));

    // 2026-09-22 is a Tuesday. A day with no count is not called zero, and
    // today carries the live count rather than the last synced one.
    expect(
      find.bySemanticsLabel(
        'Steps this week: Tuesday, 3,000 steps; Wednesday, no steps recorded; '
        'Thursday, 5,000 steps; Friday, 6,000 steps; Saturday, no steps recorded; '
        'Sunday, 4,000 steps; Today, 6,500 steps',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets("touching a day's bar shows its count", (tester) async {
    await _pump(tester, ActivityState(today: const DaySteps(steps: 6420), week: _week(), offline: false));

    final chart = tester.widget<BarChart>(find.byType(BarChart));
    // FsBarChart's tooltips: what a touch shows for each bar.
    final tooltip = chart.data.barTouchData.touchTooltipData.getTooltipItem(
      chart.data.barGroups[0], 0, chart.data.barGroups[0].barRods[0], 0,
    );
    expect(tooltip!.text, 'Tuesday · 3,000 steps');
    expect(chart.data.barTouchData.enabled, isTrue);
  });

  group('large text', () {
    /// How many lines [text] was laid out on.
    int lines(WidgetTester tester, String text) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      return boxes.map((b) => b.top.round()).toSet().length;
    }

    final big = ActivityState(
      today: const DaySteps(steps: 12345),
      week: ActivityWeek(
        days: [
          _d(22, 13000), _d(23, 12000), _d(24, 15000), _d(25, 16000),
          ActivityDay(date: '2026-09-26', steps: 14000, caloriesBurned: 1234, distanceKm: 10.52, activeMinutes: 145),
          _d(27, 14000),
          const ActivityDay(date: '2026-09-28', steps: 12345, caloriesBurned: 1234, distanceKm: 10.52, activeMinutes: 145),
        ],
        usual: 14000,
        missing: const [],
      ),
      offline: false,
    );

    for (final size in const [Size(360, 640), Size(320, 568)]) {
      testWidgets('at 2x on ${size.width.toInt()} dp nothing overflows and figures stay whole', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _pump(tester, big);
        expect(tester.takeException(), isNull);

        expect(lines(tester, '12,345'), 1, reason: 'the headline must not split mid-number');
        for (final figure in ['1234', '10.52', '145']) {
          expect(lines(tester, figure), 1, reason: figure);
        }

        await tester.scrollUntilVisible(find.text('This week'), 100);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets("at iOS's largest text the figures still stay whole", (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 3.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(tester, big);
      expect(tester.takeException(), isNull);

      expect(lines(tester, '12,345'), 1);
      for (final figure in ['1234', '10.52', '145']) {
        expect(lines(tester, figure), 1, reason: figure);
      }
      await tester.scrollUntilVisible(find.text('This week'), 100);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
