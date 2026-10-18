import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/steps/goal_step.dart';
import 'package:fitsync/features/profile/domain/profile.dart';

/// The wire values the server's `main_goal` ENUM accepts. Pinned as literals
/// on purpose: if a label is reworded to "Improve endurance" and someone
/// "fixes" the value to match, the server starts rejecting the request with a
/// 400 and this test is what catches it.
const _wireValues = [
  'lose_weight',
  'build_muscle',
  'improve_endurance',
  'general_fitness',
];

/// Holds the answers between taps, the way onboarding and Settings do.
Future<GoalAnswers Function()> _pumpLive(
  WidgetTester tester, {
  GoalAnswers initial = const GoalAnswers(),
}) async {
  var current = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => GoalStep(
              value: current,
              onChanged: (v) => setState(() => current = v),
            ),
          ),
        ),
      ),
    ),
  );
  return () => current;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// A minimal profile carrying only what `GoalAnswers.fromProfile` reads.
Profile _profileWithGoals(List<String> goals, {String? mainGoal}) => Profile(
  userId: 1,
  email: 'a@example.com',
  fullName: 'A',
  onboardingCompleted: false,
  isPremium: false,
  notificationsEnabled: true,
  equipment: const [],
  injuries: const [],
  goals: goals,
  mainGoal: mainGoal,
);

void main() {
  group('GoalAnswers.fromProfile', () {
    test('goals come back in card order, not profile order', () {
      final answers = GoalAnswers.fromProfile(
        _profileWithGoals(['general_fitness', 'lose_weight']),
      );
      expect(answers.goals, ['lose_weight', 'general_fitness']);
    });

    test('a focus among the goals is kept', () {
      final answers = GoalAnswers.fromProfile(
        _profileWithGoals([
          'lose_weight',
          'improve_endurance',
        ], mainGoal: 'improve_endurance'),
      );
      expect(answers.mainGoal, 'improve_endurance');
    });

    test('a null focus with goals falls back to the first, in card order', () {
      final answers = GoalAnswers.fromProfile(
        _profileWithGoals(['lose_weight', 'build_muscle']),
      );
      expect(answers.mainGoal, 'build_muscle');
    });

    test('a focus not among the goals falls back to the first goal', () {
      final answers = GoalAnswers.fromProfile(
        _profileWithGoals(['lose_weight'], mainGoal: 'build_muscle'),
      );
      expect(answers.mainGoal, 'lose_weight');
    });

    test('no goals means no focus', () {
      final answers = GoalAnswers.fromProfile(_profileWithGoals(const []));
      expect(answers.goals, isEmpty);
      expect(answers.mainGoal, isNull);
    });
  });

  testWidgets('renders exactly the four goals', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalStep(value: const GoalAnswers(), onChanged: (_) {}),
        ),
      ),
    );

    for (final value in _wireValues) {
      expect(find.byKey(Key('goal.$value')), findsOneWidget);
    }
    expect(find.byType(FsCard), findsNWidgets(4));
  });

  testWidgets('does not read providers or save anything', (tester) async {
    // Pumped with no ProviderScope at all. If this ever throws, the step has
    // started reaching for state it should have been handed, and Task 10's
    // reuse from Settings is broken.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalStep(
            value: const GoalAnswers(goals: ['lose_weight']),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('asks for goals, plural', (tester) async {
    await _pumpLive(tester);
    expect(find.text('What are your goals?'), findsOneWidget);
    expect(
      find.text('Pick all that apply. You can change them later.'),
      findsOneWidget,
    );
  });

  testWidgets('goals toggle and come back in card order', (tester) async {
    final answers = await _pumpLive(tester);
    await _tap(tester, 'goal.general_fitness');
    await _tap(tester, 'goal.build_muscle');
    expect(answers().goals, ['build_muscle', 'general_fitness']);
    await _tap(tester, 'goal.general_fitness');
    expect(answers().goals, ['build_muscle']);
  });

  testWidgets('the first goal ticked is the focus', (tester) async {
    final answers = await _pumpLive(tester);
    await _tap(tester, 'goal.lose_weight');
    await _tap(tester, 'goal.build_muscle');
    expect(answers().mainGoal, 'lose_weight');
  });

  testWidgets('the focus row appears only with two or more goals', (
    tester,
  ) async {
    await _pumpLive(tester);
    await _tap(tester, 'goal.build_muscle');
    // FsEyebrow renders its text upper-cased (see fs_kit.dart), the same
    // convention share_report_sheet_test.dart relies on for its own eyebrow.
    expect(find.text('MAIN FOCUS'), findsNothing);
    await _tap(tester, 'goal.lose_weight');
    expect(find.text('MAIN FOCUS'), findsOneWidget);
    expect(
      find.text('Your main focus sets your sets and reps.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('focus.build_muscle')), findsOneWidget);
    expect(find.byKey(const Key('focus.lose_weight')), findsOneWidget);
    expect(find.byKey(const Key('focus.improve_endurance')), findsNothing);
  });

  testWidgets('a focus chip switches the focus', (tester) async {
    final answers = await _pumpLive(tester);
    await _tap(tester, 'goal.build_muscle');
    await _tap(tester, 'goal.lose_weight');
    await _tap(tester, 'focus.lose_weight');
    expect(answers().mainGoal, 'lose_weight');
    expect(
      tester
          .widget<FsChip>(find.byKey(const Key('focus.lose_weight')))
          .selected,
      isTrue,
    );
  });

  testWidgets('unticking the focus moves it to the first remaining goal', (
    tester,
  ) async {
    final answers = await _pumpLive(tester);
    await _tap(tester, 'goal.improve_endurance');
    await _tap(tester, 'goal.general_fitness');
    await _tap(tester, 'goal.lose_weight');
    // Focus is improve_endurance (ticked first); untick it.
    await _tap(tester, 'goal.improve_endurance');
    expect(answers().mainGoal, 'lose_weight'); // first in card order
  });

  testWidgets('no goals means no focus', (tester) async {
    final answers = await _pumpLive(tester);
    await _tap(tester, 'goal.build_muscle');
    await _tap(tester, 'goal.build_muscle');
    expect(answers().goals, isEmpty);
    expect(answers().mainGoal, isNull);
  });

  testWidgets('ticked cards are accented', (tester) async {
    await _pumpLive(
      tester,
      initial: const GoalAnswers(
        goals: ['build_muscle'],
        mainGoal: 'build_muscle',
      ),
    );
    expect(
      tester.widget<FsCard>(find.byKey(const Key('goal.build_muscle'))).accent,
      isTrue,
    );
    expect(
      tester.widget<FsCard>(find.byKey(const Key('goal.lose_weight'))).accent,
      isFalse,
    );
  });

  testWidgets(
    'a stale focus not among the ticked goals is treated as none before '
    'toggling',
    (tester) async {
      // mainGoal here is left over from a goal that is no longer ticked --
      // the shape a seeded-but-inconsistent profile could hand the step.
      final answers = await _pumpLive(
        tester,
        initial: const GoalAnswers(
          goals: ['lose_weight'],
          mainGoal: 'build_muscle',
        ),
      );
      await _tap(tester, 'goal.improve_endurance');
      expect(answers().goals, ['lose_weight', 'improve_endurance']);
      // Not improve_endurance (just ticked) -- the already-ticked goal,
      // first in card order, since the stale focus counts as having none.
      expect(answers().mainGoal, 'lose_weight');
    },
  );

  testWidgets('unticking a non-focus goal leaves the focus unchanged', (
    tester,
  ) async {
    final answers = await _pumpLive(tester);
    await _tap(tester, 'goal.build_muscle');
    await _tap(tester, 'goal.lose_weight');
    await _tap(tester, 'goal.improve_endurance');
    expect(answers().mainGoal, 'build_muscle'); // first ticked
    // Untick a goal that is neither the one just checked nor the focus.
    await _tap(tester, 'goal.lose_weight');
    expect(answers().goals, ['build_muscle', 'improve_endurance']);
    expect(answers().mainGoal, 'build_muscle');
  });

  // The accent fill and the filled dot say which goals are ticked to anyone
  // looking; a screen reader needs the same thing said out loud.
  testWidgets('each goal card tells a screen reader whether it is ticked', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpLive(tester);

    for (final value in _wireValues) {
      expect(
        tester.getSemantics(find.byKey(Key('goal.$value'))),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: false,
        ),
      );
    }

    await _tap(tester, 'goal.build_muscle');
    expect(
      tester.getSemantics(find.byKey(const Key('goal.build_muscle'))),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('goal.lose_weight'))),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
    );
    handle.dispose();
  });
}
