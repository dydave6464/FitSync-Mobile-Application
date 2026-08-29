import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';

/// The exact shape `server/src/db/plans.js` returns.
const _planJson = {
  'planId': 42,
  'name': 'Week 1 — Full body',
  'splitStyle': 'full_body',
  'daysPerWeek': 3,
  'sessionLengthMin': 45,
  'weekNo': 1,
  'exercises': [
    {
      'exerciseId': 101,
      'name': 'Goblet squat',
      'muscleGroup': 'quadriceps',
      'thumbnailUrl': '/storage/thumbs/101.png',
      'orderNo': 1,
      'targetSets': 3,
      // A range, not a number. `plan_exercises.target_reps` is VARCHAR(255)
      // and the live generator emits "8-12".
      'targetReps': '8-12',
    },
    {
      'exerciseId': 102,
      'name': 'Push-up',
      'muscleGroup': 'chest',
      'thumbnailUrl': null,
      'orderNo': 2,
      'targetSets': 3,
      'targetReps': '10-15',
    },
  ],
};

PlanRepository _repoReturning(Object body, {int status = 200}) => PlanRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: MockClient((_) async => http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json'})),
      ),
    );

void main() {
  test('parses a plan and its exercises in order', () {
    final plan = WorkoutPlan.fromJson(Map<String, dynamic>.from(_planJson));

    expect(plan.planId, 42);
    expect(plan.name, 'Week 1 — Full body');
    expect(plan.splitStyle, 'full_body');
    expect(plan.daysPerWeek, 3);
    expect(plan.sessionLengthMin, 45);
    expect(plan.exercises, hasLength(2));
    expect(plan.exercises.first.name, 'Goblet squat');
    expect(plan.exercises.first.targetSets, 3);
    expect(plan.exercises.first.targetReps, '8-12');
    expect(plan.exercises.last.thumbnailUrl, isNull);
  });

  test('accepts a rep target the generator wrote as a plain number', () {
    // Nothing stops a future generator writing "10" into that VARCHAR.
    final plan = WorkoutPlan.fromJson({
      ..._planJson,
      'exercises': [
        {
          'exerciseId': 101,
          'name': 'Goblet squat',
          'muscleGroup': 'quadriceps',
          'orderNo': 1,
          'targetSets': 3,
          'targetReps': 10,
        },
      ],
    });

    expect(plan.exercises.single.targetReps, '10');
  });

  test('an active-plan request returns the plan', () async {
    final repo = _repoReturning({'data': {'plan': _planJson}});

    final plan = await repo.activePlan();

    expect(plan!.planId, 42);
  });

  test('no active plan is null, not an error', () async {
    // A user who is part way through onboarding legitimately has no plan.
    // Treating this as a failure would put an error screen in front of the
    // most normal state there is.
    final repo = _repoReturning({'data': {'plan': null}});

    expect(await repo.activePlan(), isNull);
  });

  test('a plan with no exercises parses to an empty list', () {
    final plan = WorkoutPlan.fromJson({
      ..._planJson,
      'exercises': <Object>[],
    });

    expect(plan.exercises, isEmpty);
  });
}
