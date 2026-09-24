import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/streaks/data/streaks_repository.dart';

ApiClient _api(MockClient client) => ApiClient(
  baseUrl: 'http://test.local',
  tokens: TokenStore(backing: InMemorySecureStore()),
  client: client,
);

void main() {
  test('read() parses the streak and its week', () async {
    final repo = StreakRepository(
      _api(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/streak');
          return http.Response(
            jsonEncode({
              'data': {
                'current': 12,
                'best': 18,
                'todayActive': true,
                'week': [
                  {'date': '2026-09-21', 'active': true},
                  {'date': '2026-09-22', 'active': false},
                ],
              },
            }),
            200,
          );
        }),
      ),
    );

    final s = await repo.read();

    expect(s.current, 12);
    expect(s.best, 18);
    expect(s.todayActive, isTrue);
    expect(s.week.map((d) => d.date), ['2026-09-21', '2026-09-22']);
    expect(s.week.map((d) => d.active), [true, false]);
  });

  test('list() and options() parse goals and the lifted-before list', () async {
    final repo = GoalsRepository(
      _api(
        MockClient((request) async {
          if (request.url.path == '/api/v1/goals/options') {
            return http.Response(
              jsonEncode({
                'data': {
                  'options': [
                    {
                      'exerciseId': 3,
                      'name': 'Bench Press',
                      'bestKg': 52.5,
                      'sets': 6,
                    },
                  ],
                },
              }),
              200,
            );
          }
          expect(request.url.path, '/api/v1/goals');
          return http.Response(
            jsonEncode({
              'data': {
                'goals': [
                  {
                    'goalId': 1,
                    'exerciseId': 3,
                    'exerciseName': 'Bench Press',
                    'targetKg': 60,
                    'bestKg': 52.5,
                    'reachedOn': null,
                  },
                  {
                    'goalId': 2,
                    'exerciseId': 4,
                    'exerciseName': 'Squat',
                    'targetKg': 80,
                    'bestKg': null,
                    'reachedOn': null,
                  },
                ],
              },
            }),
            200,
          );
        }),
      ),
    );

    final goals = await repo.list();
    expect(goals.map((g) => g.goalId), [1, 2]);
    expect(goals.first.targetKg, 60.0);
    expect(goals.first.bestKg, 52.5);
    expect(goals.last.bestKg, isNull);

    final options = await repo.options();
    expect(options.single.name, 'Bench Press');
    expect(options.single.bestKg, 52.5);
    expect(options.single.sets, 6);
  });

  test(
    'add() posts the exercise and kilograms; remove() deletes by id',
    () async {
      final seen = <String>[];
      final repo = GoalsRepository(
        _api(
          MockClient((request) async {
            seen.add('${request.method} ${request.url.path}');
            if (request.method == 'POST') {
              expect(jsonDecode(request.body), {
                'exerciseId': 3,
                'targetKg': 61.23,
              });
              return http.Response(
                jsonEncode({
                  'data': {
                    'goal': {
                      'goalId': 9,
                      'exerciseId': 3,
                      'exerciseName': 'Bench Press',
                      'targetKg': 61.23,
                      'bestKg': null,
                      'reachedOn': null,
                    },
                  },
                }),
                201,
              );
            }
            return http.Response(
              jsonEncode({
                'data': {'deleted': true},
              }),
              200,
            );
          }),
        ),
      );

      final goal = await repo.add(exerciseId: 3, targetKg: 61.23);
      await repo.remove(9);

      expect(goal.goalId, 9);
      expect(seen, ['POST /api/v1/goals', 'DELETE /api/v1/goals/9']);
    },
  );
}
