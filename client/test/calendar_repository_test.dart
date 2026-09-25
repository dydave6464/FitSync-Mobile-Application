import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/schedule/data/calendar_repository.dart';

ApiClient _api(MockClient client) => ApiClient(
  baseUrl: 'http://test.local',
  tokens: TokenStore(backing: InMemorySecureStore()),
  client: client,
);

void main() {
  test('range() asks for the dates and parses every day', () async {
    late Uri asked;
    final repo = CalendarRepository(
      _api(
        MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'data': {
                'today': '2026-09-24',
                'days': [
                  {
                    'date': '2026-09-23',
                    'workout': {'title': 'Upper/Lower', 'done': true},
                    'habits': [
                      {
                        'habitId': 3,
                        'title': 'Stretch',
                        'time': '06:30',
                        'done': true,
                      },
                    ],
                  },
                  {
                    'date': '2026-09-24',
                    'workout': null,
                    'habits': [
                      {
                        'habitId': 4,
                        'title': 'Walk',
                        'time': null,
                        'done': false,
                      },
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }),
      ),
    );

    final range = await repo.range('2026-09-23', '2026-09-24');

    expect(asked.path, '/api/v1/calendar');
    expect(asked.queryParameters, {'from': '2026-09-23', 'to': '2026-09-24'});
    expect(range.today, '2026-09-24');
    expect(range.days.map((d) => d.date), ['2026-09-23', '2026-09-24']);

    final past = range.days[0];
    expect(past.workout!.title, 'Upper/Lower');
    expect(past.workout!.done, isTrue);
    expect(past.habits.single.habitId, 3);
    expect(past.habits.single.title, 'Stretch');
    expect(past.habits.single.time, '06:30');
    expect(past.habits.single.done, isTrue);

    final today = range.days[1];
    expect(today.workout, isNull);
    expect(today.habits.single.time, isNull);
    expect(today.habits.single.done, isFalse);
  });
}
