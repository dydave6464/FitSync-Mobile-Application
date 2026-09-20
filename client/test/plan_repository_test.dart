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
      'planExerciseId': 701,
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
      'planExerciseId': 702,
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

/// A custom plan as `server/src/db/plans.js` returns it.
const _customPlanJson = {
  'planId': 9,
  'name': 'My Push / Pull / Legs',
  'splitStyle': 'push_pull_legs',
  'daysPerWeek': 3,
  'sessionLengthMin': 45,
  'weekNo': 1,
  'source': 'custom',
  'exercises': <Map<String, dynamic>>[],
};

PlanRepository _repoReturning(Object body, {int status = 200}) =>
    PlanRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

/// Captures the outgoing request so a test can assert on the URL and body,
/// not just on what came back.
PlanRepository _repoCapturing(
  Object body,
  List<http.Request> seen, {
  int status = 200,
}) => PlanRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: MockClient((req) async {
      seen.add(req);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
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
          'planExerciseId': 703,
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
    final repo = _repoReturning({
      'data': {'plan': _planJson},
    });

    final plan = await repo.activePlan();

    expect(plan!.planId, 42);
  });

  test('no active plan is null, not an error', () async {
    // A user who is part way through onboarding legitimately has no plan.
    // Treating this as a failure would put an error screen in front of the
    // most normal state there is.
    final repo = _repoReturning({
      'data': {'plan': null},
    });

    expect(await repo.activePlan(), isNull);
  });

  test('a plan with no exercises parses to an empty list', () {
    final plan = WorkoutPlan.fromJson({..._planJson, 'exercises': <Object>[]});

    expect(plan.exercises, isEmpty);
  });

  test('alternatives are parsed into candidates', () async {
    final repo = _repoReturning({
      'data': {
        'alternatives': [
          {
            'exerciseId': 12,
            'name': 'Push-up',
            'muscleGroup': 'pectorals',
            'equipment': 'Bodyweight',
            'thumbnailUrl': null,
          },
        ],
      },
    });

    final result = await repo.alternatives(77);

    expect(result.single.name, 'Push-up');
    expect(result.single.equipment, 'Bodyweight');
  });

  test('a search term is sent as q on that row\'s path', () async {
    final seen = <http.Request>[];
    final repo = _repoCapturing({
      'data': {'alternatives': []},
    }, seen);

    await repo.alternatives(77, q: 'press');

    expect(seen.single.url.path, '/api/v1/plans/exercises/77/alternatives');
    expect(seen.single.url.queryParameters['q'], 'press');
  });

  test('a swap PATCHes the row and returns the updated plan', () async {
    final seen = <http.Request>[];
    final repo = _repoCapturing({
      'data': {'plan': _planJson},
    }, seen);

    final plan = await repo.swap(701, 12);

    expect(seen.single.method, 'PATCH');
    expect(seen.single.url.path, '/api/v1/plans/exercises/701');
    expect(jsonDecode(seen.single.body), {'exerciseId': 12});
    expect(plan.planId, 42);
  });

  test('regenerate posts exactly the three overrides', () async {
    final seen = <http.Request>[];
    final repo = _repoCapturing({
      'data': {
        'plan': {
          'planId': 1,
          'name': 'Push/Pull/Legs — Build Muscle',
          'splitStyle': 'push_pull_legs',
          'daysPerWeek': 4,
          'sessionLengthMin': 60,
          'weekNo': 1,
          'days': [
            {'dayNo': 1, 'name': 'Push'},
            {'dayNo': 2, 'name': 'Pull'},
            {'dayNo': 3, 'name': 'Legs'},
          ],
          'exercises': [],
        },
      },
    }, seen);

    final plan = await repo.regenerate(
      splitStyle: 'push_pull_legs',
      daysPerWeek: 4,
      sessionLengthMin: 60,
    );

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/v1/plans/regenerate');
    expect(jsonDecode(seen.single.body), {
      'splitStyle': 'push_pull_legs',
      'daysPerWeek': 4,
      'sessionLengthMin': 60,
    });
    expect(plan.splitStyle, 'push_pull_legs');
    expect(plan.days.map((d) => d.name).toList(), ['Push', 'Pull', 'Legs']);
  });

  test('a plan says whether its user built it', () async {
    final plan = WorkoutPlan.fromJson(const {
      'planId': 1,
      'name': 'My Push / Pull / Legs',
      'splitStyle': 'push_pull_legs',
      'daysPerWeek': 3,
      'sessionLengthMin': 45,
      'weekNo': 1,
      'source': 'custom',
      'exercises': <Map<String, dynamic>>[],
    });

    expect(plan.source, 'custom');
    expect(plan.isCustom, isTrue);
  });

  test(
    'a plan from a server predating the column reads as generated',
    () async {
      // The column defaults to 'generated' server-side for the same reason: the
      // generator was the only thing that could make one.
      final plan = WorkoutPlan.fromJson(const {
        'planId': 1,
        'name': 'Week 1 — Full body',
        'splitStyle': 'full_body',
        'daysPerWeek': 3,
        'sessionLengthMin': 45,
        'weekNo': 1,
        'exercises': <Map<String, dynamic>>[],
      });

      expect(plan.source, 'generated');
      expect(plan.isCustom, isFalse);
    },
  );

  test('sending a workout to the plan posts what the server needs', () async {
    late Map<String, dynamic> sent;
    final repo = PlanRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {'plan': _customPlanJson},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final plan = await repo.planFromSession(
      sessionId: 32,
      splitStyle: 'push_pull_legs',
    );

    expect(sent['sessionId'], 32);
    expect(sent['splitStyle'], 'push_pull_legs');
    expect(plan.isCustom, isTrue);
  });

  test('replacing a day sends the day it replaces', () async {
    late Map<String, dynamic> sent;
    final repo = PlanRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {'plan': _customPlanJson},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await repo.planFromSession(sessionId: 32, dayNo: 2);

    expect(sent['dayNo'], 2);
    expect(
      sent.containsKey('splitStyle'),
      isFalse,
      reason: 'extending an existing plan states no split style',
    );
  });

  test('regenerating over a custom plan says so explicitly', () async {
    late Map<String, dynamic> sent;
    final repo = PlanRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {'plan': _customPlanJson},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await repo.regenerate(
      splitStyle: 'full_body',
      daysPerWeek: 3,
      sessionLengthMin: 45,
      replaceCustomPlan: true,
    );

    expect(sent['replaceCustomPlan'], isTrue);
  });

  test('an ordinary regenerate does not claim to replace anything', () async {
    // The server refuses by default. Sending the flag unasked would defeat the
    // guard for every caller at once.
    late Map<String, dynamic> sent;
    final repo = PlanRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {'plan': _customPlanJson},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await repo.regenerate(
      splitStyle: 'full_body',
      daysPerWeek: 3,
      sessionLengthMin: 45,
    );

    expect(sent.containsKey('replaceCustomPlan'), isFalse);
  });
}
