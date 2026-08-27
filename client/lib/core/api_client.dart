import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Talks to the FitSync API and unwraps its envelope.
///
/// Every response is either `{ data: ... }` or
/// `{ error: { code, message, details } }`. Unwrapping here, once, means no
/// screen has to know that shape and every failure arrives as an
/// [ApiException] carrying the server's own code.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const _timeout = Duration(seconds: 10);

  final http.Client _client;
  final String _baseUrl;

  /// Needed by widgets that build image URLs from a relative storage path.
  String get baseUrl => _baseUrl;

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

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (_) {
      // The three causes are indistinguishable from here, and the third is by
      // far the most common in development, so name it.
      throw ApiException(
        'NETWORK_ERROR',
        'Could not reach $_baseUrl. Check the server is running, and that '
            '"adb reverse tcp:3000 tcp:3000" has been run since the device last '
            'connected.',
      );
    }

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
}
