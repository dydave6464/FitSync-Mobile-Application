import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/reminders/data/reminder_repository.dart';

ReminderRepository _repo(MockClient client) => ReminderRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: client,
  ),
);

const _settings = {
  'habitsEnabled': true,
  'habitLeadMin': 15,
  'workoutEnabled': true,
  'workoutTime': '18:30',
  'checkinEnabled': false,
  'checkinTime': '07:00',
};

void main() {
  test('read() parses the settings', () async {
    final repo = _repo(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/reminders/settings');
        return http.Response(
          jsonEncode({
            'data': {'settings': _settings},
          }),
          200,
        );
      }),
    );
    final s = await repo.read();
    expect(s.habitsEnabled, isTrue);
    expect(s.habitLeadMin, 15);
    expect(s.workoutEnabled, isTrue);
    expect(s.workoutTime, '18:30');
    expect(s.checkinEnabled, isFalse);
  });

  test(
    'patch() sends only the fields given and returns the full settings',
    () async {
      final repo = _repo(
        MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(jsonDecode(request.body), {'workoutTime': '18:30'});
          return http.Response(
            jsonEncode({
              'data': {'settings': _settings},
            }),
            200,
          );
        }),
      );
      expect((await repo.patch({'workoutTime': '18:30'})).workoutTime, '18:30');
    },
  );
}
