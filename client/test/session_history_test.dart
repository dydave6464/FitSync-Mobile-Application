import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';

SessionRepository _repo(MockClient client) => SessionRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: client,
  ),
);

/// The exact shape `server/src/db/sessions.js` returns for one finished
/// session -- the real numbers from a manual workout, so the parsing is
/// pinned against something that actually came back.
const _entryJson = {
  'sessionId': 32,
  'sessionDate': '2026-09-14',
  'startedAt': '2026-09-14T09:15:00.000Z',
  'durationMin': 2,
  'totalVolumeKg': 2953.0,
  'setCount': 21,
  'exerciseCount': 4,
  'planName': null,
};

void main() {
  group('history', () {
    test('parses a finished session', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'sessions': [_entryJson],
                'total': 1,
                'page': 1,
                'limit': 20,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final page = await repo.history();
      final entry = page.sessions.single;
      expect(entry.sessionId, 32);
      expect(entry.sessionDate, '2026-09-14');
      expect(entry.durationMin, 2);
      expect(entry.totalVolumeKg, 2953.0);
      expect(entry.setCount, 21);
      expect(entry.exerciseCount, 4);
      expect(page.total, 1);
    });

    test('a session with no plan is the user\'s own', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'sessions': [_entryJson],
                'total': 1,
                'page': 1,
                'limit': 20,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final entry = (await repo.history()).sessions.single;
      expect(entry.planName, isNull);
      expect(entry.title, 'Your own workout');
    });

    test('a plan session is titled by its plan', () async {
      // The plan it RAN under, which the server reads at query time -- so
      // regenerating since does not rename what you already did.
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'sessions': [
                  {..._entryJson, 'planName': 'Upper Body · Push'},
                ],
                'total': 1,
                'page': 1,
                'limit': 20,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect((await repo.history()).sessions.single.title, 'Upper Body · Push');
    });

    test('an integer volume is not an error', () async {
      // jsonDecode hands back 2953 as an int; MySQL's DECIMAL may round to a
      // whole number, so `as double` would throw on perfectly good data.
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'sessions': [
                  {..._entryJson, 'totalVolumeKg': 2953},
                ],
                'total': 1,
                'page': 1,
                'limit': 20,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      expect((await repo.history()).sessions.single.totalVolumeKg, 2953.0);
    });

    test('a session that logged nothing still parses', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'sessions': [
                  {..._entryJson, 'totalVolumeKg': null, 'durationMin': null},
                ],
                'total': 1,
                'page': 1,
                'limit': 20,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final entry = (await repo.history()).sessions.single;
      expect(entry.totalVolumeKg, isNull);
      expect(entry.durationMin, isNull);
    });

    test('asks for the page it was given', () async {
      late Uri asked;
      final repo = _repo(
        MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'data': {'sessions': [], 'total': 0, 'page': 2, 'limit': 5},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await repo.history(page: 2, limit: 5);
      expect(asked.queryParameters['page'], '2');
      expect(asked.queryParameters['limit'], '5');
    });
  });

  group('summary', () {
    test('parses the totals', () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'summary': {
                  'sessionCount': 2,
                  'setCount': 14,
                  'totalVolumeKg': 1500.0,
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final summary = await repo.summary(period: 'week');
      expect(summary.sessionCount, 2);
      expect(summary.setCount, 14);
      expect(summary.totalVolumeKg, 1500.0);
    });

    test('asks for the period it was given', () async {
      late Uri asked;
      final repo = _repo(
        MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'data': {
                'summary': {
                  'sessionCount': 0,
                  'setCount': 0,
                  'totalVolumeKg': 0,
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await repo.summary(period: 'month');
      expect(asked.queryParameters['period'], 'month');
    });

    test('an untrained account reads as zero, not as missing', () async {
      // The state that sent a user hunting for a bug. It has to parse into
      // real zeroes so the screen can say "nothing yet" rather than fail.
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'summary': {
                  'sessionCount': 0,
                  'setCount': 0,
                  'totalVolumeKg': 0,
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final summary = await repo.summary(period: 'week');
      expect(summary.totalVolumeKg, 0);
      expect(summary.isEmpty, isTrue);
    });
  });
}
