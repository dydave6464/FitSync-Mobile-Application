import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';

RoutineRepository _repo(MockClient client) => RoutineRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: client,
  ),
);

const _dayJson = {
  'date': '2026-09-21',
  'habits': [
    {
      'habitId': 1,
      'title': 'Mobility',
      'time': '06:30',
      'durationMin': 8,
      'weekdays': [1, 3],
      'done': true,
    },
    {
      'habitId': 2,
      'title': 'Walk',
      'time': null,
      'durationMin': null,
      'weekdays': [1],
      'done': false,
    },
  ],
  'workout': {'title': 'Upper Body', 'done': false},
};

void main() {
  test('reads the day, its habits and the workout item', () async {
    final repo = _repo(
      MockClient((request) async {
        expect(request.url.path, '/api/v1/routine/today');
        return http.Response(jsonEncode({'data': _dayJson}), 200);
      }),
    );
    final day = await repo.today();

    expect(day.date, '2026-09-21');
    expect(day.habits.first.subtitle, '6:30 AM · 8 min');
    expect(day.habits.last.subtitle, '');
    expect(day.habits.last.time, isNull);
    expect(day.workout!.title, 'Upper Body');
    expect(day.total, 3);
    expect(day.done, 1);
  });

  test('screen order: timed habits, then untimed and the workout by title', () {
    final day = RoutineDay.fromJson(_dayJson);
    expect(day.entries.map((e) => e.title), ['Mobility', 'Upper Body', 'Walk']);
    expect(day.entries[1], isA<WorkoutEntry>());
  });

  test('no workout item reads as null', () {
    final day = RoutineDay.fromJson({..._dayJson, 'workout': null});
    expect(day.workout, isNull);
    expect(day.total, 2);
  });

  test('withHabitDone changes one habit and nothing else', () {
    final day = RoutineDay.fromJson(_dayJson).withHabitDone(2, true);
    expect(day.habits.map((h) => h.done), [true, true]);
    expect(day.done, 2);
  });

  test('formatClock reads 24-hour times as 12-hour', () {
    expect(formatClock('00:05'), '12:05 AM');
    expect(formatClock('12:00'), '12:00 PM');
    expect(formatClock('21:30'), '9:30 PM');
  });

  test('add, edit, remove, check and uncheck hit the right routes', () async {
    final calls = <String>[];
    final bodies = <Map<String, dynamic>>[];
    final habit = (_dayJson['habits'] as List).first;
    final repo = _repo(
      MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.body.isNotEmpty) {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        if (request.url.path.endsWith('/check')) {
          return http.Response(
            jsonEncode({
              'data': {'done': request.method == 'PUT'},
            }),
            200,
          );
        }
        if (request.method == 'DELETE') {
          return http.Response('{"data":{"deleted":true}}', 200);
        }
        return http.Response(
          jsonEncode({
            'data': {'habit': habit},
          }),
          request.method == 'POST' ? 201 : 200,
        );
      }),
    );
    const draft = HabitDraft(
      title: 'Mobility',
      time: '06:30',
      durationMin: null,
      weekdays: [1, 3],
    );

    await repo.add(draft);
    await repo.edit(1, draft);
    await repo.check(1);
    await repo.uncheck(1);
    await repo.remove(1);

    expect(calls, [
      'POST /api/v1/routine/habits',
      'PATCH /api/v1/routine/habits/1',
      'PUT /api/v1/routine/habits/1/check',
      'DELETE /api/v1/routine/habits/1/check',
      'DELETE /api/v1/routine/habits/1',
    ]);
    // A draft sends every field, null included: on PATCH, null clears.
    expect(bodies.first, {
      'title': 'Mobility',
      'time': '06:30',
      'durationMin': null,
      'weekdays': [1, 3],
    });
  });
}
