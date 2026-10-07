import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/sessions/data/training_settings_repository.dart';

TrainingSettingsRepository _repo(MockClient client) =>
    TrainingSettingsRepository(
      ApiClient(
        baseUrl: 'http://test.local',
        tokens: TokenStore(backing: InMemorySecureStore()),
        client: client,
      ),
    );

http.Response _settings(int restSeconds) => http.Response(
  jsonEncode({
    'data': {
      'settings': {'restSeconds': restSeconds},
    },
  }),
  200,
);

void main() {
  test('restSeconds() reads the saved rest time', () async {
    final repo = _repo(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/training/settings');
        return _settings(150);
      }),
    );
    expect(await repo.restSeconds(), 150);
  });

  test(
    'setRestSeconds() sends only the rest time and answers what was stored',
    () async {
      final repo = _repo(
        MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/training/settings');
          expect(jsonDecode(request.body), {'restSeconds': 120});
          return _settings(120);
        }),
      );
      expect(await repo.setRestSeconds(120), 120);
    },
  );
}
