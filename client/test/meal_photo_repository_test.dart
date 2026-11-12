import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_repository.dart';
import 'package:fitsync/features/nutrition/domain/meal_photo.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';

ApiClient _api(MockClient client) => ApiClient(
  baseUrl: 'http://test.local',
  tokens: TokenStore(backing: InMemorySecureStore()),
  client: client,
);

void main() {
  test('recognize posts the photo as base64 with its type', () async {
    final repo = MealPhotoRepository(
      _api(
        MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, '/api/v1/nutrition/recognize');
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          expect(body, {
            'image': base64Encode([0xFF, 0xD8, 0xFF]),
            'mimeType': 'image/jpeg',
          });
          return http.Response(
            jsonEncode({
              'data': {
                'recognitionId': 3,
                'remainingToday': 14,
                'items': [],
                'unlisted': [],
              },
            }),
            200,
          );
        }),
      ),
    );
    final r = await repo.recognize(
      Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      'image/jpeg',
    );
    expect([r.recognitionId, r.remainingToday, r.isEmpty], [3, 14, true]);
  });

  test('recognize passes the server\'s error code through', () async {
    final repo = MealPhotoRepository(
      _api(
        MockClient(
          (r) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'PHOTO_LIMIT_REACHED',
                'message':
                    "You've used today's meal photos. Try again tomorrow.",
              },
            }),
            429,
          ),
        ),
      ),
    );
    await expectLater(
      repo.recognize(Uint8List(3), 'image/jpeg'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'PHOTO_LIMIT_REACHED',
        ),
      ),
    );
  });

  test(
    'log posts the confirmed items and returns how many were logged',
    () async {
      final repo = MealPhotoRepository(
        _api(
          MockClient((r) async {
            expect(r.url.path, '/api/v1/nutrition/recognitions/3/log');
            expect(jsonDecode(r.body), {
              'date': '2026-10-25',
              'mealType': 'lunch',
              'items': [
                {
                  'itemId': 40,
                  'servings': 1.5,
                  'food': {'source': 'local', 'id': 1},
                },
              ],
            });
            return http.Response(
              jsonEncode({
                'data': {
                  'entries': [{}, {}],
                },
              }),
              201,
            );
          }),
        ),
      );
      const rice = Food(
        source: 'local',
        id: 1,
        name: 'White rice',
        kcal: 206,
        proteinG: 3.4,
        carbsG: 47.5,
        fatG: 0.3,
      );
      final n = await repo.log(
        recognitionId: 3,
        date: '2026-10-25',
        mealType: 'lunch',
        items: const [PhotoLogItem(itemId: 40, servings: 1.5, food: rice)],
      );
      expect(n, 2);
    },
  );

  test('the photo call waits longer than the usual 10 seconds', () {
    expect(MealPhotoRepository.recognizeTimeout, const Duration(seconds: 45));
  });

  test('postJson honours a per-call timeout', () async {
    final api = _api(
      MockClient((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response(jsonEncode({'data': {}}), 200);
      }),
    );
    await expectLater(
      api.postJson('/x', const {}, timeout: const Duration(milliseconds: 20)),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
      ),
    );
    expect(await api.postJson('/x', const {}), isEmpty);
  });

  test('recognize hands its cancel to the request', () async {
    final api = _RecordingApi();
    final cancel = Completer<void>();
    await MealPhotoRepository(api).recognize(Uint8List.fromList([0xFF, 0xD8, 0xFF]), 'image/jpeg', cancel: cancel.future);
    expect(identical(api.abortTrigger, cancel.future), isTrue);
    expect(api.timeout, MealPhotoRepository.recognizeTimeout);
  });

  // NU-15: the capture sheet's allowance, asked before a photo.
  test('today gets the allowance and any unlogged photo', () async {
    final repo = MealPhotoRepository(
      _api(
        MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.url.path, '/api/v1/nutrition/recognitions/today');
          return http.Response(
            jsonEncode({
              'data': {'limit': 15, 'remainingToday': 3, 'unlogged': null},
            }),
            200,
          );
        }),
      ),
    );
    final t = await repo.today();
    expect([t.limit, t.remainingToday, t.unlogged], [15, 3, null]);
  });

  // getJson has no timeout of its own to pass.
  testWidgets('today gives up after 5 seconds', (tester) async {
    Object? error;
    unawaited(MealPhotoRepository(_SlowGetApi()).today().then<void>((_) {}, onError: (Object e) => error = e));
    await tester.pump(const Duration(milliseconds: 4900));
    expect(error, isNull);
    await tester.pump(const Duration(milliseconds: 200));
    expect(error, isA<TimeoutException>());
  });
}

/// Never answers a GET.
class _SlowGetApi extends ApiClient {
  _SlowGetApi() : super(baseUrl: 'http://test.local', tokens: TokenStore(backing: InMemorySecureStore()));

  @override
  Future<Map<String, dynamic>> getJson(String path, {Map<String, Object?> query = const {}}) =>
      Completer<Map<String, dynamic>>().future;
}

/// Records what the repository asks of the API, and answers an empty photo.
class _RecordingApi extends ApiClient {
  _RecordingApi() : super(baseUrl: 'http://test.local', tokens: TokenStore(backing: InMemorySecureStore()));

  Future<void>? abortTrigger;
  Duration? timeout;

  @override
  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body, {Duration? timeout, Future<void>? abortTrigger}) async {
    this.timeout = timeout;
    this.abortTrigger = abortTrigger;
    return {'recognitionId': 1, 'remainingToday': 14, 'items': [], 'unlisted': []};
  }
}

