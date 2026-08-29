import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';

ApiClient clientReturning(String body, {int status = 200, void Function(http.Request)? onRequest}) {
  final mock = MockClient((request) async {
    onRequest?.call(request);
    return http.Response(body, status, headers: {'content-type': 'application/json'});
  });
  // An in-memory token store, because the real one reaches a platform channel
  // that has no binding under `flutter test`.
  return ApiClient(
    client: mock,
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
  );
}

void main() {
  test('unwraps the data envelope', () async {
    final api = clientReturning(jsonEncode({'data': {'total': 3}}));
    final data = await api.getJson('/api/v1/exercises');
    expect(data['total'], 3);
  });

  test('maps the error envelope to an ApiException carrying the server code', () async {
    final api = clientReturning(
      jsonEncode({'error': {'code': 'INVALID_QUERY_PARAM', 'message': 'limit must not exceed 50.'}}),
      status: 400,
    );
    expect(
      () => api.getJson('/api/v1/exercises'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'INVALID_QUERY_PARAM')
          .having((e) => e.message, 'message', contains('50'))),
    );
  });

  test('a non-JSON body is reported as INVALID_RESPONSE, not a parse crash', () async {
    final api = clientReturning('<html>502 Bad Gateway</html>', status: 502);
    expect(
      () => api.getJson('/api/v1/exercises'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
    );
  });

  test('a transport failure is reported as NETWORK_ERROR with a usable hint', () async {
    final api = ApiClient(
      client: MockClient((_) async => throw const SocketExceptionStub()),
      baseUrl: 'http://test.local',
      tokens: TokenStore(backing: InMemorySecureStore()),
    );
    expect(
      () => api.getJson('/api/v1/exercises'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'NETWORK_ERROR')
          .having((e) => e.message, 'message', contains('adb reverse'))),
    );
  });

  test('null and empty query values are omitted from the URL', () async {
    Uri? seen;
    final api = clientReturning(
      jsonEncode({'data': {}}),
      onRequest: (r) => seen = r.url,
    );
    await api.getJson('/api/v1/exercises', query: {
      'muscleGroup': 'abs',
      'equipment': null,
      'page': '1',
      'blank': '',
    });
    expect(seen!.queryParameters, {'muscleGroup': 'abs', 'page': '1'});
  });

  test('a response with neither data nor error is rejected', () async {
    final api = clientReturning(jsonEncode({'unexpected': true}));
    expect(
      () => api.getJson('/api/v1/exercises'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
    );
  });

  test('attaches the bearer token when one is stored', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('abc.def.ghi');
    String? seen;
    final client = ApiClient(
      tokens: tokens,
      client: MockClient((req) async {
        seen = req.headers['Authorization'];
        return http.Response('{"data":{}}', 200);
      }),
    );
    await client.getJson('/api/v1/profile');
    expect(seen, 'Bearer abc.def.ghi');
  });

  test('sends no Authorization header when no token is stored', () async {
    String? seen;
    final client = ApiClient(
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient((req) async {
        seen = req.headers['Authorization'];
        return http.Response('{"data":{}}', 200);
      }),
    );
    await client.getJson('/api/v1/exercises');
    expect(seen, isNull, reason: 'an anonymous request must not send an empty header');
  });

  test('postJson sends a JSON body and unwraps the envelope', () async {
    String? body;
    final client = ApiClient(
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient((req) async {
        body = req.body;
        expect(req.headers['Content-Type'], contains('application/json'));
        return http.Response('{"data":{"token":"t"}}', 201);
      }),
    );
    final data = await client.postJson('/api/v1/auth/login', {'email': 'a@b.com'});
    expect(jsonDecode(body!), {'email': 'a@b.com'});
    expect(data['token'], 't');
  });

  test('a write that fails surfaces the server code', () async {
    final client = ApiClient(
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient((_) async => http.Response(
          '{"error":{"code":"EMAIL_TAKEN","message":"That email is already registered."}}', 409)),
    );
    await expectLater(
      client.postJson('/api/v1/auth/register', const {}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'EMAIL_TAKEN')),
    );
  });

  test('a write that cannot reach the server raises NETWORK_ERROR', () async {
    final client = ApiClient(
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient((_) async => throw const SocketException('refused')),
    );
    await expectLater(
      client.postJson('/api/v1/auth/login', const {}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR')),
    );
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'Connection refused';
}
