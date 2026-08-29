import 'dart:convert';

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
  /// far the most common in development, so name it.
  String get _unreachableMessage =>
      'Could not reach $_baseUrl. Check the server is running, and that '
      '"adb reverse tcp:3000 tcp:3000" has been run since the device last '
      'connected.';

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
      throw ApiException(
        error['code'] as String? ?? 'UNKNOWN_ERROR',
        error['message'] as String? ?? 'The request failed.',
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

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String?> query = const {},
  }) async {
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value != null && value.isNotEmpty) params[key] = value;
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
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = await _headers(json: true);
    final encoded = jsonEncode(body);

    final http.Response response;
    try {
      response = await switch (method) {
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PATCH' => _client.patch(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        _ => throw ArgumentError('Unsupported method: $method'),
      }
          .timeout(_timeout);
    } catch (_) {
      throw ApiException('NETWORK_ERROR', _unreachableMessage);
    }
    return _unwrap(response);
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) =>
      _send('POST', path, body);
  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body);
  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body);
}
