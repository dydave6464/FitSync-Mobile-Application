import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/make_plan_sheet.dart';

const _generated = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  source: 'generated',
  exercises: [],
);

/// What the sheet resolved to, once it has: `(true, slug)` for an answer
/// (null slug being Cancel or a dismissal), `(false, null)` while it is open.
typedef _Outcome = ({bool closed, String? split});

Future<_Outcome Function()> _open(
  WidgetTester tester, {
  WorkoutPlan? replacing,
}) async {
  _Outcome outcome = (closed: false, split: null);
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final split = await showMakePlanSheet(
                context,
                replacing: replacing,
              );
              outcome = (closed: true, split: split);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => outcome;
}

FsButton _button(WidgetTester tester, String key) =>
    tester.widget<FsButton>(find.byKey(Key(key)));

void main() {
  group('over a plan the user did not build', () {
    testWidgets('names the plan that goes', (tester) async {
      await _open(tester, replacing: _generated);

      expect(find.text('Make this your plan'), findsOneWidget);
      expect(
        find.text(
          'This replaces "Week 1 — Full body". You can\'t get it back.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Replace my plan is red, beside a plain Cancel', (
      tester,
    ) async {
      await _open(tester, replacing: _generated);

      final replace = _button(tester, 'makePlan.confirm');
      expect(replace.label, 'Replace my plan');
      expect(replace.danger, isTrue);
      expect(replace.kind, FsButtonKind.ghost);

      final cancel = _button(tester, 'makePlan.cancel');
      expect(cancel.label, 'Cancel');
      expect(cancel.danger, isFalse);
    });

    testWidgets('sends the split chosen on it', (tester) async {
      final outcome = await _open(tester, replacing: _generated);

      await tester.tap(find.byKey(const Key('makePlan.split.upper_lower')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('makePlan.confirm')));
      await tester.pumpAndSettle();

      expect(outcome(), (closed: true, split: 'upper_lower'));
    });

    testWidgets('Cancel sends nothing', (tester) async {
      final outcome = await _open(tester, replacing: _generated);

      await tester.tap(find.byKey(const Key('makePlan.cancel')));
      await tester.pumpAndSettle();

      expect(outcome(), (closed: true, split: null));
    });

    testWidgets('a tap outside sends nothing', (tester) async {
      final outcome = await _open(tester, replacing: _generated);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('Make this your plan'), findsNothing);
      expect(outcome(), (closed: true, split: null));
    });
  });

  group('with no plan yet', () {
    testWidgets('replaces nothing, so says nothing about it', (tester) async {
      await _open(tester);

      expect(find.text('Make this your plan'), findsOneWidget);
      expect(find.textContaining('This replaces'), findsNothing);
    });

    testWidgets('Make it my plan sends Full body unless changed', (
      tester,
    ) async {
      final outcome = await _open(tester);

      final make = _button(tester, 'makePlan.confirm');
      expect(make.label, 'Make it my plan');
      expect(make.kind, FsButtonKind.primary);
      expect(make.danger, isFalse);

      await tester.tap(find.byKey(const Key('makePlan.confirm')));
      await tester.pumpAndSettle();

      expect(outcome(), (closed: true, split: 'full_body'));
    });
  });

  testWidgets('offers the four splits, one at a time, Full body first', (
    tester,
  ) async {
    await _open(tester);

    for (final value in [
      'full_body',
      'push_pull_legs',
      'upper_lower',
      'cardio_core',
    ]) {
      expect(find.byKey(Key('makePlan.split.$value')), findsOneWidget);
    }
    bool selected(String value) => tester
        .widget<FsChip>(find.byKey(Key('makePlan.split.$value')))
        .selected;
    expect(selected('full_body'), isTrue);

    await tester.tap(find.byKey(const Key('makePlan.split.cardio_core')));
    await tester.pumpAndSettle();

    expect(selected('cardio_core'), isTrue);
    expect(selected('full_body'), isFalse);
    expect(find.text('Names your plan and its days.'), findsOneWidget);
  });

  testWidgets('fits a 320 dp phone at 2.0× text, buttons reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final outcome = await _open(tester, replacing: _generated);
    expect(tester.takeException(), isNull);

    for (final key in ['makePlan.confirm', 'makePlan.cancel']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
      );
    }
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('makePlan.confirm'))),
      isSemantics(
        label: 'Replace my plan',
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();

    await tester.tap(find.byKey(const Key('makePlan.confirm')));
    await tester.pumpAndSettle();
    expect(outcome(), (closed: true, split: 'full_body'));
  });
}
