import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/activity/data/activity_repository.dart';

ApiClient _api(MockClient client) => ApiClient(
  baseUrl: 'http://test.local',
  tokens: TokenStore(backing: InMemorySecureStore()),
  client: client,
);

void main() {
  test('saveDay PUTs the steps to the day and reads the saved day back', () async {
    late http.Request seen;
    final repo = ActivityRepository(_api(MockClient((request) async {
      seen = request;
      return http.Response(jsonEncode({'data': {
        'date': '2026-09-28', 'steps': 6420, 'caloriesBurned': 158,
        'distanceKm': 4.52, 'activeMinutes': 64, 'missing': <String>[],
      }}), 200);
    })));

    final day = await repo.saveDay('2026-09-28', 6420);

    expect(seen.method, 'PUT');
    expect(seen.url.path, '/api/v1/activity/2026-09-28');
    expect(jsonDecode(seen.body), {'steps': 6420});
    expect(day.steps, 6420);
    expect(day.distanceKm, 4.52);
  });

  test('week GETs the seven days', () async {
    late http.Request seen;
    final repo = ActivityRepository(_api(MockClient((request) async {
      seen = request;
      return http.Response(jsonEncode({'data': {
        'days': [
          for (var d = 22; d <= 28; d++)
            {'date': '2026-09-$d', 'steps': null, 'caloriesBurned': null,
             'distanceKm': null, 'activeMinutes': null},
        ],
        'usual': null, 'usualDays': 0, 'missing': ['height', 'weight'],
      }}), 200);
    })));

    final week = await repo.week();

    expect(seen.method, 'GET');
    expect(seen.url.path, '/api/v1/activity');
    expect(week.days, hasLength(7));
    expect(week.missingHeight, isTrue);
  });
}
