// Logging help: the empty reps box shows the target range. Its own file:
// exercise_log_panel_test.dart is the extraction's safety net and stays
// unmodified.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/presentation/widgets/exercise_log_panel.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

PlanExercise _exercise({String reps = '8-12'}) => PlanExercise(
  planExerciseId: 601,
  exerciseId: 101,
  name: 'Goblet squat',
  muscleGroup: 'quadriceps',
  orderNo: 1,
  targetSets: 3,
  targetReps: reps,
  equipment: 'dumbbell',
);

ActiveSession _session() => const ActiveSession(
  sessionId: 7,
  status: 'in_progress',
  sessionDate: '2026-09-08',
  sets: [],
);

Future<void> _pump(WidgetTester tester, {PlanExercise? exercise}) async {
  final drafts = SetDrafts();
  addTearDown(drafts.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseLogPanel(
            exercise: exercise ?? _exercise(),
            session: _session(),
            drafts: drafts,
            onUndoSet: (_) async {},
          ),
        ),
      ),
    ),
  );
}

/// What an empty box shows. A widget rather than hintText -- it shrinks to
/// fit at large text -- so this reads the text drawn inside the field.
String? _hintOf(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .data;

void main() {
  testWidgets('the empty reps box shows the target range', (tester) async {
    await _pump(tester);

    expect(_hintOf(tester, 'set.1.reps'), '8-12');
  });

  // The range is data, so it is drawn in the readable grey, not the faint
  // caption colour that fails contrast.
  testWidgets('the reps hint is readable grey', (tester) async {
    await _pump(tester);

    // What is drawn, not just what the decoration asks for: the hint is a
    // widget of its own now, and hintStyle does not reach one.
    final drawn = tester
        .renderObject<RenderParagraph>(
          find.descendant(
            of: find.byKey(const Key('set.1.reps')),
            matching: find.text('8-12'),
          ),
        )
        .text
        .style;
    expect(drawn?.color, FsTokens.light.text2);
  });

  // With the hint now a number, a screen reader still has to hear which box
  // this is, typed into or not.
  testWidgets('the boxes are announced as Weight and Reps', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    // The field's own node sits on its EditableText; asking from the
    // TextField itself walks up to the card instead.
    String labelOf(String key) => tester
        .getSemantics(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(EditableText),
          ),
        )
        .label;
    expect(labelOf('set.1.reps'), contains('Reps'));
    expect(labelOf('set.1.weight'), contains('Weight'));
    handle.dispose();
  });

  testWidgets('with no target range, the reps box still says reps', (
    tester,
  ) async {
    await _pump(tester, exercise: _exercise(reps: ''));

    expect(_hintOf(tester, 'set.1.reps'), 'reps');
  });

  testWidgets('fits a 320 dp phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester);

    expect(tester.takeException(), isNull);
  });

  // The range is the number to aim for, so an ellipsis cutting "15-20" to
  // "15…" loses the half that says when to stop. At 2x on a 320 dp phone it
  // shrinks to fit the box instead.
  testWidgets('a long range shows whole in the reps box at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, exercise: _exercise(reps: '15-20'));

    final hint = find.descendant(
      of: find.byKey(const Key('set.1.reps')),
      matching: find.text('15-20'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(hint);
    expect(paragraph.didExceedMaxLines, isFalse);
    final box = tester.getRect(find.byKey(const Key('set.1.reps')));
    final drawn = tester.getRect(hint);
    expect(drawn.left, greaterThanOrEqualTo(box.left));
    expect(drawn.right, lessThanOrEqualTo(box.right));
    // Still centred in its box, as the typed number is.
    expect(drawn.center.dx, moreOrLessEquals(box.center.dx, epsilon: 1));
    expect(tester.takeException(), isNull);
  });
}
