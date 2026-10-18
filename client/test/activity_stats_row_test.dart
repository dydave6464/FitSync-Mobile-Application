import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:fitsync/core/theme.dart';

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

/// Activity that cannot be read.
class _FailingActivity extends ActivityController {
  @override
  Future<ActivityState> build() async => throw StateError('offline');
  @override
  Future<void> sync() async {}
}

ActivityWeek _week({List<String> missing = const [], int? usual}) =>
    ActivityWeek(
      days: [
        for (var d = 22; d <= 28; d++)
          ActivityDay(
            date: '2026-09-$d',
            steps: d == 28 ? 6420 : null,
            caloriesBurned: d == 28 ? 158 : null,
            distanceKm: d == 28 ? 4.52 : null,
            activeMinutes: d == 28 ? 64 : null,
          ),
      ],
      usual: usual,
      missing: missing,
    );

Future<void> _pump(
  WidgetTester tester,
  _Permission permission, {
  ActivityWeek? week,
  int steps = 6420,
  bool fail = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stepPermissionProvider.overrideWithValue(permission),
        activityProvider.overrideWith(
          () => fail
              ? _FailingActivity()
              : _StubActivity(
                  ActivityState(
                    today: DaySteps(steps: steps),
                    week: week ?? _week(),
                    offline: false,
                  ),
                ),
        ),
        liveStepsProvider.overrideWith((ref) => const Stream<int>.empty()),
      ],
      child: const MaterialApp(home: Scaffold(body: ActivityStatsRow())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Finder tile(String key, String value) => find.descendant(
    of: find.byKey(Key('home.activity.$key')),
    matching: find.text(value),
  );

  testWidgets(
    'not turned on: three zero tiles, any of them opens the activation screen',
    (tester) async {
      await _pump(tester, _Permission(StepAccess.notAsked));

      expect(tile('steps', '0'), findsOneWidget);
      expect(tile('kcal', '0'), findsOneWidget);
      expect(tile('km', '0.0'), findsOneWidget);
      expect(find.text('Tap to start counting your steps'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home.activity.kcal')));
      await tester.pumpAndSettle();
      expect(find.byType(ActivationScreen), findsOneWidget);
    },
  );

  testWidgets(
    'refused: zero tiles; a tap asks again, then opens Settings if still refused',
    (tester) async {
      final permission = _Permission(StepAccess.refused);
      await _pump(tester, permission);

      expect(tile('steps', '0'), findsOneWidget);
      expect(find.text('Step counting is off — tap to allow'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home.activity.steps')));
      await tester.pumpAndSettle();
      expect(permission.log, ['request', 'settings']);
    },
  );

  testWidgets(
    'refused, granted when asked again: no Settings, the stats show',
    (tester) async {
      final permission = _Permission(
        StepAccess.refused,
        onRequest: StepAccess.granted,
      );
      await _pump(tester, permission);

      expect(find.text('Step counting is off — tap to allow'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home.activity.km')));
      await tester.pumpAndSettle();
      expect(permission.log, ['request']);
      expect(tile('steps', '6,420'), findsOneWidget);
      expect(find.text('Step counting is off — tap to allow'), findsNothing);
    },
  );

  testWidgets(
    'while step access loads: zero tiles that do nothing when tapped',
    (tester) async {
      final pending = Completer<StepAccess>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stepPermissionProvider.overrideWithValue(
              _PendingPermission(pending.future),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ActivityStatsRow())),
        ),
      );
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
    },
  );

  testWidgets('on: steps, kcal and km, each opening Activity', (tester) async {
    await _pump(tester, _Permission(StepAccess.granted));

    expect(
      find.descendant(
        of: find.byKey(const Key('home.activity.steps')),
        matching: find.text('6,420'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home.activity.kcal')),
        matching: find.text('158'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home.activity.km')),
        matching: find.text('4.5'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('home.activity.km')));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
  });

  testWidgets('on, weight missing: kcal is a dash, km stays', (tester) async {
    await _pump(
      tester,
      _Permission(StepAccess.granted),
      week: _week(missing: ['weight']),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('home.activity.kcal')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home.activity.km')),
        matching: find.text('4.5'),
      ),
      findsOneWidget,
    );
  });

  group('the tiles', () {
    FaIcon iconIn(WidgetTester tester, String key) => tester.widget<FaIcon>(
      find.descendant(
        of: find.byKey(Key('home.activity.$key')),
        matching: find.byType(FaIcon),
      ),
    );

    testWidgets('each kind has its own icon and colour', (tester) async {
      await _pump(tester, _Permission(StepAccess.granted));
      final t = tester.element(find.byKey(const Key('home.activity.steps'))).fs;

      for (final (key, icon, color) in [
        ('steps', FontAwesomeIcons.personWalking, t.blue),
        ('kcal', FontAwesomeIcons.fire, t.amber),
        ('km', FontAwesomeIcons.locationDot, t.violet),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('home.activity.$key')),
            matching: find.byIcon(icon.data),
          ),
          findsOneWidget,
          reason: key,
        );
        expect(iconIn(tester, key).color, color, reason: key);
      }
    });

    testWidgets('the same icons show before counting is on', (tester) async {
      await _pump(tester, _Permission(StepAccess.notAsked));
      expect(find.byIcon(FontAwesomeIcons.personWalking.data), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.fire.data), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.locationDot.data), findsOneWidget);
    });

    testWidgets('the words under the numbers are a readable size', (
      tester,
    ) async {
      await _pump(tester, _Permission(StepAccess.granted));
      for (final label in ['steps', 'kcal', 'km']) {
        final style = tester.widget<Text>(find.text(label)).style!;
        expect(style.fontSize, greaterThanOrEqualTo(12), reason: label);
      }
    });
  });

  testWidgets('at 2x text on a small phone, no figure breaks across lines', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      _Permission(StepAccess.granted),
      week: _week(usual: 8000),
    );
    expect(tester.takeException(), isNull);

    // "6,420" read as "6," then "42" then "0" when it wrapped.
    for (final words in ['6,420', '158', '4.5', 'steps', 'kcal', 'km']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(words));
      final lines = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: words.length),
          )
          .map((box) => box.top)
          .toSet();
      expect(lines, hasLength(1), reason: words);
    }
  });

  group("today's steps against the usual", () {
    double fill(WidgetTester tester) => tester
        .widget<FractionallySizedBox>(
          find.byKey(const Key('home.activity.usual')),
        )
        .widthFactor!;

    testWidgets('the steps tile fills to the share of the usual done', (
      tester,
    ) async {
      await _pump(
        tester,
        _Permission(StepAccess.granted),
        week: _week(usual: 8000),
      );
      expect(fill(tester), closeTo(6420 / 8000, 1e-9));
      // Said in words too: the bar is drawn, not read.
      expect(
        find.bySemanticsLabel(RegExp('80% of your usual 8,000 steps')),
        findsOneWidget,
      );
    });

    testWidgets('a day past the usual is a full bar, never more', (
      tester,
    ) async {
      await _pump(
        tester,
        _Permission(StepAccess.granted),
        week: _week(usual: 5000),
      );
      expect(fill(tester), 1.0);
    });

    testWidgets('steps that fail to load offer a retry with the same icon', (
      tester,
    ) async {
      await _pump(tester, _Permission(StepAccess.granted), fail: true);
      final retry = find.byKey(const Key('home.activity.retry'));
      expect(retry, findsOneWidget);
      expect(
        find.descendant(
          of: retry,
          matching: find.byIcon(FontAwesomeIcons.personWalking.data),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a usual of nothing draws no bar', (tester) async {
      await _pump(
        tester,
        _Permission(StepAccess.granted),
        week: _week(usual: 0),
      );
      expect(find.byKey(const Key('home.activity.usual')), findsNothing);
    });

    testWidgets('the zero tiles before counting draw no bar', (tester) async {
      await _pump(
        tester,
        _Permission(StepAccess.notAsked),
        week: _week(usual: 8000),
      );
      expect(find.byKey(const Key('home.activity.usual')), findsNothing);
    });

    // Home sits below these tiles now: the bar arriving, or never coming,
    // must not move what is under them.
    testWidgets('the steps tile is one height, bar or no bar', (tester) async {
      Future<double> height(_Permission permission, ActivityWeek week) async {
        await _pump(tester, permission, week: week);
        return tester
            .getSize(find.byKey(const Key('home.activity.steps')))
            .height;
      }

      final withBar = await height(
        _Permission(StepAccess.granted),
        _week(usual: 8000),
      );
      expect(await height(_Permission(StepAccess.granted), _week()), withBar);
      expect(await height(_Permission(StepAccess.notAsked), _week()), withBar);
    });

    testWidgets('no usual yet, no bar', (tester) async {
      await _pump(tester, _Permission(StepAccess.granted));
      expect(find.byKey(const Key('home.activity.usual')), findsNothing);
    });
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
