import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';

const _userJson = {
  'userId': 7,
  'email': 'juan@example.com',
  'fullName': 'Juan Dela Cruz',
  'onboardingCompleted': false,
  'isPremium': false,
};

ApiClient _clientReturning(String body, int status, {TokenStore? tokens}) => ApiClient(
      tokens: tokens ?? TokenStore(backing: InMemorySecureStore()),
      client: MockClient((_) async => http.Response(body, status)),
    );

void main() {
  test('login stores the token and returns the user', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(jsonEncode({'data': {'user': _userJson, 'token': 'tok'}}), 200,
          tokens: tokens),
      tokens,
    );
    final user = await repo.login('juan@example.com', 's3cret-pass');
    expect(user.email, 'juan@example.com');
    expect(user.onboardingCompleted, isFalse);
    expect(await tokens.read(), 'tok', reason: 'the token must be persisted, not just returned');
  });

  test('a failed login stores nothing', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(
          jsonEncode({'error': {'code': 'INVALID_CREDENTIALS', 'message': 'Email or password is incorrect.'}}),
          401,
          tokens: tokens),
      tokens,
    );
    await expectLater(repo.login('a@b.com', 'wrong'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_CREDENTIALS')));
    expect(await tokens.read(), isNull, reason: 'a failed sign-in must leave no token behind');
  });

  test('register stores the token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(jsonEncode({'data': {'user': _userJson, 'token': 'tok'}}), 201,
          tokens: tokens),
      tokens,
    );
    await repo.register(email: 'a@b.com', password: 's3cret-pass', fullName: 'A');
    expect(await tokens.read(), 'tok');
  });

  test('signOut clears the token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final repo = AuthRepository(_clientReturning('{"data":{}}', 200, tokens: tokens), tokens);
    await repo.signOut();
    expect(await tokens.read(), isNull);
  });
}
