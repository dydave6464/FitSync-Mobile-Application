import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';

/// The exact shape `server/src/db/sessions.js` returns.
const _sessionJson = {
  'sessionId': 7,
  'planId': 42,
  'status': 'in_progress',
  'sessionDate': '2026-09-08',
  'startedAt': '2026-09-08T09:15:00.000Z',
  'durationMin': null,
  'totalVolumeKg': null,
  'sets': [
    {'exerciseId': 101, 'setNumber': 1, 'weightKg': 22.5, 'reps': 10},
    {'exerciseId': 101, 'setNumber': 2, 'weightKg': null, 'reps': null},
  ],
};

SessionRepository _repo(MockClient client) => SessionRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: client,
      ),
    );

/// A manual session's exercise rows, exactly as
/// `server/src/db/sessions.js` joins them and the route resolves them.
const _manualExerciseJson = {
  'sessionExerciseId': 5,
  'exerciseId': 101,
  'orderNo': 1,
  'targetSets': 3,
  'targetReps': '8-12',
  'name': 'Incline DB Press',
  'muscleGroup': 'pectorals',
  'thumbnailUrl': '/storage/exercises/0001/thumb.jpg',
};

void main() {
  group('a session carrying its own exercises', () {
    test('reads them as plan exercises the logger can draw', () {
      final session = ActiveSession.fromJson({
        ..._sessionJson,
        'planId': null,
        'planDayNo': null,
        'exercises': [_manualExerciseJson],
      });

      final only = session.exercises.single;
      expect(only.exerciseId, 101);
      expect(only.name, 'Incline DB Press');
      expect(only.muscleGroup, 'pectorals');
      expect(only.thumbnailUrl, '/storage/exercises/0001/thumb.jpg');
      expect(only.targetSets, 3);
      expect(only.targetReps, '8-12');
      expect(only.orderNo, 1);
    });

    test('stands the session row in for the plan row identity', () {
      // PlanExercise.planExerciseId is a row identity, and a manually chosen
      // exercise has no plan row to take one from.
      final session = ActiveSession.fromJson({
        ..._sessionJson,
        'exercises': [_manualExerciseJson],
      });

      expect(session.exercises.single.planExerciseId, 5);
    });

    test('a plan-backed session carries none', () {
      // The server sends an empty list there; the logger falls back to the
      // plan, which is still where a plan session's exercises live.
      final session = ActiveSession.fromJson({..._sessionJson, 'exercises': []});

      expect(session.exercises, isEmpty);
    });

    test('a payload predating the field reads as none, not as a crash', () {
      final session = ActiveSession.fromJson(_sessionJson);

      expect(session.exercises, isEmpty);
    });
  });


  test('active() returns null when nothing is in progress', () async {
    final repo = _repo(MockClient((_) async =>
        http.Response(jsonEncode({'data': {'session': null}}), 200)));

    expect(await repo.active(), isNull);
  });

  test('active() parses a session and its sets', () async {
    final repo = _repo(MockClient((_) async =>
        http.Response(jsonEncode({'data': {'session': _sessionJson}}), 200)));

    final session = await repo.active();

    expect(session!.sessionId, 7);
    expect(session.status, 'in_progress');
    expect(session.sets, hasLength(2));
    expect(session.setFor(101, 1)!.weightKg, 22.5);
    // A bodyweight set: logged, but with nothing to record.
    expect(session.setFor(101, 2)!.weightKg, isNull);
    expect(session.setFor(101, 2)!.reps, isNull);
    expect(session.setFor(999, 1), isNull);
    expect(session.completedSetCount, 2);
    expect(session.startedAt, DateTime.utc(2026, 9, 8, 9, 15));
  });

  test('an integer weight from JSON still parses as a double', () async {
    final repo = _repo(MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'session': {
                ..._sessionJson,
                'sets': [
                  // jsonDecode gives an int here, not a double -- casting
                  // straight to double? would throw.
                  {'exerciseId': 101, 'setNumber': 1, 'weightKg': 20, 'reps': 8},
                ],
              },
            },
          }),
          200,
        )));

    final session = await repo.active();
    expect(session!.setFor(101, 1)!.weightKg, 20.0);
  });

  test('start() posts and returns the session', () async {
    late String method;
    late String path;
    final repo = _repo(MockClient((request) async {
      method = request.method;
      path = request.url.path;
      return http.Response(jsonEncode({'data': {'session': _sessionJson}}), 201);
    }));

    final session = await repo.start();

    expect(method, 'POST');
    expect(path, '/api/v1/sessions');
    expect(session.sessionId, 7);
  });

  test('start() with exercises posts them in the chosen order', () async {
    late Map<String, dynamic> body;
    final repo = _repo(MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'data': {'session': _sessionJson}}), 201);
    }));

    await repo.start(exerciseIds: const [303, 101, 202]);

    expect(body['exerciseIds'], [303, 101, 202]);
  });

  test('start() with no exercises sends no list at all', () async {
    // An absent key is what the endpoint reads as "start today's plan
    // session". Sending an empty array instead is a 400.
    late Map<String, dynamic> body;
    final repo = _repo(MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'data': {'session': _sessionJson}}), 201);
    }));

    await repo.start();

    expect(body.containsKey('exerciseIds'), isFalse);
  });

  test('logSet() puts the set and returns what the server stored', () async {
    late Map<String, dynamic> body;
    final repo = _repo(MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {
            'set': {'exerciseId': 101, 'setNumber': 3, 'weightKg': 25.0, 'reps': 8},
          },
        }),
        200,
      );
    }));

    final stored = await repo.logSet(7, exerciseId: 101, setNumber: 3, weightKg: 25, reps: 8);

    expect(body, {'exerciseId': 101, 'setNumber': 3, 'weightKg': 25.0, 'reps': 8});
    expect(stored.setNumber, 3);
    expect(stored.weightKg, 25.0);
  });

  test('deleteSet() addresses the set in the path', () async {
    late String method;
    late String path;
    final repo = _repo(MockClient((request) async {
      method = request.method;
      path = request.url.path;
      return http.Response(jsonEncode({'data': {'deleted': true}}), 200);
    }));

    await repo.deleteSet(7, exerciseId: 101, setNumber: 2);

    expect(method, 'DELETE');
    expect(path, '/api/v1/sessions/7/sets/101/2');
  });

  test('complete() sends the elapsed minutes', () async {
    late Map<String, dynamic> body;
    final repo = _repo(MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {
            'session': {..._sessionJson, 'status': 'completed', 'durationMin': 47, 'totalVolumeKg': 380.0},
          },
        }),
        200,
      );
    }));

    final done = await repo.complete(7, 47);

    expect(body, {'durationMin': 47});
    expect(done.status, 'completed');
    expect(done.totalVolumeKg, 380.0);
  });

  test('complete() parses a whole-number totalVolumeKg as a double', () async {
    final repo = _repo(MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              // jsonDecode gives an int here when the server's DECIMAL
              // happens to round to a whole number -- this must not throw.
              'session': {..._sessionJson, 'status': 'completed', 'totalVolumeKg': 380},
            },
          }),
          200,
        )));

    final done = await repo.complete(7, 47);

    expect(done.totalVolumeKg, 380.0);
  });

  test('abandon() posts to the abandon route and completes without throwing', () async {
    late String method;
    late String path;
    final repo = _repo(MockClient((request) async {
      method = request.method;
      path = request.url.path;
      return http.Response(jsonEncode({'data': {'abandoned': true}}), 200);
    }));

    await repo.abandon(7);

    expect(method, 'POST');
    expect(path, '/api/v1/sessions/7/abandon');
  });

  test('lastPerformance() batches the ids into one query string', () async {
    late Uri uri;
    final repo = _repo(MockClient((request) async {
      uri = request.url;
      return http.Response(
        jsonEncode({
          'data': {
            'performances': [
              {'exerciseId': 101, 'weightKg': 22.5, 'reps': 10, 'sessionDate': '2026-09-05'},
            ],
          },
        }),
        200,
      );
    }));

    final byExercise = await repo.lastPerformance([101, 102, 103]);

    expect(uri.queryParameters['exerciseIds'], '101,102,103');
    expect(byExercise[101]!.weightKg, 22.5);
    expect(byExercise[102], isNull);
  });

  test('lastPerformance() parses a whole-number weightKg as a double', () async {
    final repo = _repo(MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'performances': [
                // jsonDecode gives an int here, not a double -- casting
                // straight to double? would throw.
                {'exerciseId': 101, 'weightKg': 20, 'reps': 8, 'sessionDate': '2026-09-05'},
              ],
            },
          }),
          200,
        )));

    final byExercise = await repo.lastPerformance([101]);

    expect(byExercise[101]!.weightKg, 20.0);
  });

  test('lastPerformance() with no ids never reaches the network', () async {
    var called = false;
    final repo = _repo(MockClient((_) async {
      called = true;
      return http.Response('{"data":{"performances":[]}}', 200);
    }));

    expect(await repo.lastPerformance([]), isEmpty);
    expect(called, isFalse);
  });

  test('completedThisWeek() returns the dates as a set', () async {
    final repo = _repo(MockClient((_) async => http.Response(
          jsonEncode({'data': {'dates': ['2026-09-07', '2026-09-09']}}), 200)));

    expect(await repo.completedThisWeek(), {'2026-09-07', '2026-09-09'});
  });

  test('a server error surfaces as an ApiException carrying its code', () async {
    final repo = _repo(MockClient((_) async => http.Response(
          jsonEncode({
            'error': {'code': 'NO_ACTIVE_PLAN', 'message': 'You have no active plan to train.'},
          }),
          409,
        )));

    expect(
      () => repo.start(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NO_ACTIVE_PLAN')),
    );
  });

  // ActiveSession.withSet / withoutSet -- the fold-without-refetch the
  // controller uses so one logged set updates state without a second round
  // trip. Pure in-memory model logic: no HTTP involved.

  test('withSet replaces an existing set for the same exerciseId/setNumber', () {
    const session = ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      sets: [LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 8)],
    );

    final updated =
        session.withSet(const LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 25, reps: 10));

    expect(updated.sets, hasLength(1));
    expect(updated.setFor(101, 1)!.weightKg, 25);
    expect(updated.setFor(101, 1)!.reps, 10);
  });

  test('withSet appends a new set and keeps the list ordered by exerciseId then setNumber', () {
    // 102 sorts after 101 by construction; inserting 101 here would land at
    // the end of the list if withSet only appended, so this only stays
    // ordered if the sort is actually running.
    const session = ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      sets: [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 8),
        LoggedSet(exerciseId: 103, setNumber: 1, weightKg: 30, reps: 6),
      ],
    );

    final updated =
        session.withSet(const LoggedSet(exerciseId: 102, setNumber: 1, weightKg: 25, reps: 10));

    expect(updated.sets, hasLength(3));
    expect(
      updated.sets.map((s) => s.exerciseId).toList(),
      [101, 102, 103],
    );
  });

  test('withoutSet removes only the matching set, not others sharing its setNumber', () {
    // Same setNumber, different exerciseId -- the case a one-field match
    // would wrongly delete.
    const session = ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      sets: [
        LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 8),
        LoggedSet(exerciseId: 102, setNumber: 1, weightKg: 30, reps: 6),
      ],
    );

    final updated = session.withoutSet(101, 1);

    expect(updated.sets, hasLength(1));
    expect(updated.setFor(101, 1), isNull);
    expect(updated.setFor(102, 1)!.weightKg, 30);
  });

  test('withSet preserves every other field on the session', () {
    final startedAt = DateTime.utc(2026, 9, 8, 9, 15);
    final session = ActiveSession(
      sessionId: 7,
      status: 'in_progress',
      sessionDate: '2026-09-08',
      planId: 42,
      startedAt: startedAt,
      durationMin: 30,
      totalVolumeKg: 500.0,
      sets: const [],
      planDayNo: 2,
    );

    final updated =
        session.withSet(const LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 8));

    expect(updated.sessionId, 7);
    expect(updated.status, 'in_progress');
    expect(updated.sessionDate, '2026-09-08');
    expect(updated.planId, 42);
    expect(updated.startedAt, startedAt);
    expect(updated.durationMin, 30);
    expect(updated.totalVolumeKg, 500.0);
    // The copy-helper trap: dropping planDayNo here would blank the day on
    // the first logged set, and a day-2 session would re-filter to day 1
    // mid-workout.
    expect(updated.planDayNo, 2);
  });
}
