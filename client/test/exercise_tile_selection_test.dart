import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/widgets/exercise_tile.dart';

const _exercise = ExerciseSummary(
  exerciseId: 101,
  name: 'Incline DB Press',
  muscleGroup: 'pectorals',
  equipment: 'Dumbbell',
  thumbnailUrl: null,
);

const _risky = ExerciseSummary(
  exerciseId: 202,
  name: 'Barbell Deadlift',
  muscleGroup: 'glutes',
  equipment: 'Barbell',
  thumbnailUrl: null,
  contraindicated: true,
);

Future<void> _pump(
  WidgetTester tester, {
  bool selected = false,
  ExerciseSummary exercise = _exercise,
}) => tester.pumpWidget(
  MaterialApp(
    theme: fsLightTheme(),
    home: Scaffold(
      body: ExerciseTile(
        exercise: exercise,
        baseUrl: 'http://test.local',
        onTap: () {},
        selected: selected,
        onInfo: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('an exercise not chosen shows an empty mark', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('tile.select.101')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a chosen exercise is ticked', (tester) async {
    await _pump(tester, selected: true);

    expect(find.byKey(const Key('tile.select.101')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('an exercise that loads a reported injury is marked', (
    tester,
  ) async {
    // The generator refuses these outright. Someone picking by hand should at
    // least be told, rather than discovering it from their back.
    await _pump(tester, selected: false, exercise: _risky);

    expect(find.byKey(const Key('tile.risk.202')), findsOneWidget);
  });

  testWidgets('a safe exercise carries no warning', (tester) async {
    await _pump(tester, selected: false);

    expect(find.byKey(const Key('tile.risk.101')), findsNothing);
  });
}
