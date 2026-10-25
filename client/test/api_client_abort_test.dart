import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';

/// A raw local socket, so the test sees exactly when the app hangs up: the
/// meal photo server stops its work only when the app's connection closes.
void main() {
  late ServerSocket server;
  late ApiClient api;
  late Completer<void> hungUp;
  var answer = true;

  setUp(() async {
    answer = true;
    hungUp = Completer<void>();
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      final received = StringBuffer();
      socket.listen(
        (bytes) {
          received.write(utf8.decode(bytes));
          // Like a server still waiting on Groq: read the request, never answer.
          if (!answer || !received.toString().contains('{"a":1}')) return;
          const body = '{"data":{"ok":true}}';
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
            'Content-Length: ${body.length}\r\nConnection: close\r\n\r\n$body',
          );
          socket.close();
        },
        onDone: () {
          if (!hungUp.isCompleted) hungUp.complete();
          socket.destroy();
        },
      );
    });
    api = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      tokens: TokenStore(backing: InMemorySecureStore()),
    );
  });
  tearDown(() => server.close());

  test('an abort ends the call as CANCELLED and the app hangs up', () async {
    answer = false;
    final cancel = Completer<void>();
    final call = api.postJson('/x', const {
      'a': 1,
    }, abortTrigger: cancel.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(hungUp.isCompleted, isFalse, reason: 'the request is open, waiting');
    cancel.complete();
    await expectLater(
      call,
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CANCELLED')),
    );
    await hungUp.future.timeout(const Duration(seconds: 2));
  });

  test('its own timeout hangs up too, and reads as no connection', () async {
    answer = false;
    final call = api.postJson(
      '/x',
      const {'a': 1},
      timeout: const Duration(milliseconds: 200),
      abortTrigger: Completer<void>().future,
    );
    await expectLater(
      call,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
      ),
    );
    await hungUp.future.timeout(const Duration(seconds: 2));
  });

  test(
    'with an abort trigger that never fires, the call answers as usual',
    () async {
      final data = await api.postJson('/x', const {
        'a': 1,
      }, abortTrigger: Completer<void>().future);
      expect(data, {'ok': true});
    },
  );
}
