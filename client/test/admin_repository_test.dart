import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/admin/data/admin_repository.dart';

void main() {
  test('me reads the admin from /admin/me with the stored token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('admin-tok');
    late http.Request sent;
    final api = ApiClient(
      tokens: tokens,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'data': {
              'admin': {
                'id': 3,
                'email': 'admin@fitsync.ph',
                'fullName': 'Ana Reyes',
              },
            },
          }),
          200,
        );
      }),
    );

    final admin = await AdminRepository(api).me();

    expect(sent.method, 'GET');
    expect(sent.url.path, '/api/v1/admin/me');
    expect(sent.headers['Authorization'], 'Bearer admin-tok');
    expect(admin.id, 3);
    expect(admin.email, 'admin@fitsync.ph');
    expect(admin.fullName, 'Ana Reyes');
  });

  test('a refused admin token surfaces as UNAUTHENTICATED', () async {
    final api = ApiClient(
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'Sign in again to continue.',
            },
          }),
          401,
        ),
      ),
    );

    await expectLater(
      AdminRepository(api).me(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHENTICATED'),
      ),
    );
  });
}
