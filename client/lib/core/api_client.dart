import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_store.dart';

/// Talks to the FitSync API and unwraps its envelope.
///
/// Every response is either `{ data: ... }` or
/// `{ error: { code, message, details } }`. Unwrapping here, once, means no
/// screen has to know that shape and every failure arrives as an
/// [ApiException] carrying the server's own code.
///
/// The stored JWT is attached here too, so no screen ever handles a token.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, TokenStore? tokens})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl,
      _tokens = tokens ?? TokenStore();

  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const _timeout = Duration(seconds: 10);

  final http.Client _client;
  final String _baseUrl;
  final TokenStore _tokens;

  /// Needed by widgets that build image URLs from a relative storage path.
  String get baseUrl => _baseUrl;

  /// One wording for every unreachable-server failure, read or write.
  ///
  /// The three causes are indistinguishable from here, and the third is by
  /// far the most common in development, so a debug build names it. A
  /// release build names neither the address nor the adb command: users
  /// cannot act on either, and screens show [userMessage] in any case.
  @visibleForTesting
  static String unreachableMessage(String baseUrl, {bool debug = kDebugMode}) =>
      debug
      ? 'Could not reach $baseUrl. Check the server is running, and that '
            '"adb reverse tcp:3000 tcp:3000" has been run since the device '
            'last connected.'
      : 'Could not reach the server.';

  String get _unreachableMessage => unreachableMessage(_baseUrl);

  Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final token = await _tokens.read();
    // Omit the header entirely rather than sending an empty one — the server
    // rejects a malformed Authorization header, and anonymous routes
    // (register, login) must stay reachable before a token exists.
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _unwrap(http.Response response) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        'INVALID_RESPONSE',
        'Server returned a non-JSON body (HTTP ${response.statusCode}).',
      );
    }

    final error = body['error'];
    if (error is Map<String, dynamic>) {
      final details = error['details'];
      throw ApiException(
        error['code'] as String? ?? 'UNKNOWN_ERROR',
        error['message'] as String? ?? 'The request failed.',
        // Only the `{ field }`-style objects a screen can use; anything else
        // the server sent there is dropped rather than failing the cast.
        details: details is List
            ? details.whereType<Map<String, dynamic>>().toList(growable: false)
            : const [],
      );
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException(
        'INVALID_RESPONSE',
        'Response carried neither a data nor an error object.',
      );
    }
    return data;
  }

  /// A value may be a single [String] or a [List] of them; a list is sent as
  /// a repeated key, which is what a filter meaning "any of these" looks like
  /// on the wire. Empty strings and empty lists are dropped, so an absent
  /// filter and a blank one mean the same thing.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    final params = <String, dynamic>{};
    query.forEach((key, value) {
      if (value is List<String>) {
        final kept = value.where((v) => v.isNotEmpty).toList(growable: false);
        if (kept.isNotEmpty) params[key] = kept;
      } else if (value is String && value.isNotEmpty) {
        params[key] = value;
      }
    });

    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: params.isEmpty ? null : params);
    final headers = await _headers();

    final http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    } catch (_) {
      throw ApiException('NETWORK_ERROR', _unreachableMessage);
    }

    return _unwrap(response);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
    Future<void>? abortTrigger,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = await _headers(json: true);
    final encoded = jsonEncode(body);

    final http.Response response;
    try {
      // The outer timeout bounds everything, connection setup included; the
      // abortable request's own timer is what hangs up so the server stops.
      response = abortTrigger != null
          ? await _sendAbortable(method, uri, headers, encoded, abortTrigger, timeout ?? _timeout)
              .timeout(timeout ?? _timeout)
          : await switch (method) {
              'POST' => _client.post(uri, headers: headers, body: encoded),
              'PATCH' => _client.patch(uri, headers: headers, body: encoded),
              'PUT' => _client.put(uri, headers: headers, body: encoded),
              'DELETE' => _client.delete(uri, headers: headers, body: encoded),
              _ => throw ArgumentError('Unsupported method: $method'),
            }.timeout(timeout ?? _timeout);
    } on http.RequestAbortedException {
      throw const ApiException('CANCELLED', 'The request was cancelled.');
    } catch (_) {
      throw ApiException('NETWORK_ERROR', _unreachableMessage);
    }
    return _unwrap(response);
  }

  /// A request that is dropped -- its connection closed, so the server can
  /// stop work nobody is waiting for any more -- when [abortTrigger]
  /// completes (throws [http.RequestAbortedException]) or when [timeout]
  /// passes (throws [TimeoutException]). A plain Future.timeout would stop
  /// waiting but leave the connection, and the server's work, running.
  Future<http.Response> _sendAbortable(
    String method,
    Uri uri,
    Map<String, String> headers,
    String body,
    Future<void> abortTrigger,
    Duration timeout,
  ) async {
    final stop = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!stop.isCompleted) stop.complete();
    });
    unawaited(abortTrigger.then((_) {
      if (!stop.isCompleted) stop.complete();
    }));
    final request = http.AbortableRequest(method, uri, abortTrigger: stop.future)
      ..headers.addAll(headers)
      ..body = body;
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.RequestAbortedException {
      if (timedOut) throw TimeoutException('No answer within $timeout', timeout);
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  /// [timeout] replaces the usual 10 seconds for a request known to take
  /// longer: Snap a meal waits for the AI. With an [abortTrigger], the
  /// request is dropped (its connection closed, so the server stops) when the
  /// trigger completes -- this then throws an [ApiException] with code
  /// CANCELLED -- or when [timeout] passes (NETWORK_ERROR, as without one).
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
    Future<void>? abortTrigger,
  }) => _send('POST', path, body, timeout: timeout, abortTrigger: abortTrigger);
  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) => _send('PATCH', path, body);
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) => _send('PUT', path, body);

  /// The server answers a delete with `{ data: { … } }` like every other
  /// route — never 204 — because [_unwrap] requires a `data` object.
  Future<Map<String, dynamic>> deleteJson(String path) =>
      _send('DELETE', path, const {});
}
