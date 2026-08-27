import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';

ApiClient clientReturning(String body, {int status = 200, void Function(http.Request)? onRequest}) {
  final mock = MockClient((request) async {
    onRequest?.call(request);
    return http.Response(body, status, headers: {'content-type': 'application/json'});
  });
  return ApiClient(client: mock, baseUrl: 'http://test.local');
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
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'Connection refused';
}
