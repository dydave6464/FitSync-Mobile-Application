import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/presentation/exercise_detail_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/plan_screen.dart';
import 'package:fitsync/features/settings/presentation/settings_screen.dart';

const _plan = WorkoutPlan(
  planId: 42,
  name: 'Week 1 — Full body',
  splitStyle: 'full_body',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      exerciseId: 101,
      name: 'Goblet squat',
      muscleGroup: 'quadriceps',
      orderNo: 1,
      targetSets: 3,
      targetReps: 10,
    ),
    PlanExercise(
      exerciseId: 102,
      name: 'Push-up',
      muscleGroup: 'chest',
      orderNo: 2,
      targetSets: 3,
      targetReps: 12,
    ),
  ],
);

/// Keeps anything downstream of the API client off the platform channel.
ApiClient _hermeticClient() => ApiClient(
      baseUrl: 'http://test.local',
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient((_) async => http.Response('{"data":{}}', 200)),
    );

Future<void> _pump(WidgetTester tester, WorkoutPlan? plan) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_hermeticClient()),
      activePlanProvider.overrideWith((ref) async => plan),
    ],
    child: const MaterialApp(home: PlanScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the plan summary', (tester) async {
    await _pump(tester, _plan);

    expect(find.text('Week 1 — Full body'), findsOneWidget);
    expect(find.textContaining('3 days a week'), findsOneWidget);
    expect(find.textContaining('Full body'), findsWidgets);
  });

  testWidgets('renders every exercise with its sets and reps', (tester) async {
    await _pump(tester, _plan);

    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('Push-up'), findsOneWidget);
    expect(find.textContaining('3 × 10'), findsOneWidget);
    expect(find.textContaining('3 × 12'), findsOneWidget);
  });

  testWidgets('tapping an exercise opens its detail screen', (tester) async {
    await _pump(tester, _plan);

    await tester.tap(find.text('Goblet squat'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
  });

  testWidgets('offers a way into Settings', (tester) async {
    await _pump(tester, _plan);

    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('no plan yet renders an empty state, not a crash',
      (tester) async {
    await _pump(tester, null);

    expect(find.byKey(const Key('noPlan')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
