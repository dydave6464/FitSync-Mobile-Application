import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/domain/sign_in_outcome.dart';

const _userJson = {
  'userId': 7,
  'email': 'juan@example.com',
  'fullName': 'Juan Dela Cruz',
  'onboardingCompleted': false,
  'isPremium': false,
};

ApiClient _clientReturning(String body, int status, {TokenStore? tokens}) =>
    ApiClient(
      tokens: tokens ?? TokenStore(backing: InMemorySecureStore()),
      client: MockClient((_) async => http.Response(body, status)),
    );

void main() {
  test('login stores the token and returns the user', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(
        jsonEncode({
          'data': {'user': _userJson, 'token': 'tok'},
        }),
        200,
        tokens: tokens,
      ),
      tokens,
    );
    final outcome = await repo.login('juan@example.com', 's3cret-pass');
    final user = (outcome as TraineeSignedIn).user;
    expect(user.email, 'juan@example.com');
    expect(user.onboardingCompleted, isFalse);
    expect(
      await tokens.read(),
      'tok',
      reason: 'the token must be persisted, not just returned',
    );
    expect(
      await tokens.readRole(),
      'trainee',
      reason: 'a server from before roles sends none: it only has trainees',
    );
  });

  test('a trainee login with its role is a trainee sign-in', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    // The phone was last used by an admin: the role must not stick.
    await tokens.writeRole('admin');
    final repo = AuthRepository(
      _clientReturning(
        jsonEncode({
          'data': {'role': 'trainee', 'user': _userJson, 'token': 'tok'},
        }),
        200,
        tokens: tokens,
      ),
      tokens,
    );

    final outcome = await repo.login('juan@example.com', 's3cret-pass');

    expect(outcome, isA<TraineeSignedIn>());
    expect((outcome as TraineeSignedIn).user.userId, 7);
    expect(await tokens.read(), 'tok');
    expect(await tokens.readRole(), 'trainee');
  });

  test('an admin login stores the admin role and returns the admin', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    late http.Request sent;
    final repo = AuthRepository(
      ApiClient(
        tokens: tokens,
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'data': {
                'role': 'admin',
                'admin': {
                  'id': 1,
                  'email': 'admin@fitsync.ph',
                  'fullName': 'Ana Reyes',
                },
                'token': 'admin-tok',
              },
            }),
            200,
          );
        }),
      ),
      tokens,
    );

    final outcome = await repo.login('admin@fitsync.ph', 'admin-pass');

    expect(sent.url.path, '/api/v1/auth/login');
    expect(outcome, isA<AdminSignedIn>());
    final admin = (outcome as AdminSignedIn).admin;
    expect(admin.id, 1);
    expect(admin.email, 'admin@fitsync.ph');
    expect(admin.fullName, 'Ana Reyes');
    expect(await tokens.read(), 'admin-tok');
    expect(
      await tokens.readRole(),
      'admin',
      reason: 'the next launch checks this token with /admin/me',
    );
  });

  test('a Google sign-in stores the trainee role', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.writeRole('admin');
    final repo = AuthRepository(
      _clientReturning(
        jsonEncode({
          'data': {'user': _userJson, 'token': 'google-tok'},
        }),
        200,
        tokens: tokens,
      ),
      tokens,
    );

    final user = await repo.signInWithGoogle('id-token');

    expect(user.email, 'juan@example.com');
    expect(await tokens.read(), 'google-tok');
    expect(
      await tokens.readRole(),
      'trainee',
      reason: 'Google sign-in is trainee-only',
    );
  });

  test('a failed login stores nothing', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(
        jsonEncode({
          'error': {
            'code': 'INVALID_CREDENTIALS',
            'message': 'Email or password is incorrect.',
          },
        }),
        401,
        tokens: tokens,
      ),
      tokens,
    );
    await expectLater(
      repo.login('a@b.com', 'wrong'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'INVALID_CREDENTIALS',
        ),
      ),
    );
    expect(
      await tokens.read(),
      isNull,
      reason: 'a failed sign-in must leave no token behind',
    );
  });

  test('register does not store a token', () async {
    // Registration no longer returns a token: the account exists but cannot
    // sign in until the address is verified, so the response carries only
    // the user.
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(
        jsonEncode({
          'data': {'user': _userJson},
        }),
        201,
        tokens: tokens,
      ),
      tokens,
    );
    await repo.register(
      email: 'a@b.com',
      password: 's3cret-pass',
      fullName: 'A',
    );
    expect(
      await tokens.read(),
      isNull,
      reason:
          'there is nothing to authenticate with until the address is verified',
    );
  });

  test('requestPasswordReset posts the email', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning('{"data":{}}', 202, tokens: tokens),
      tokens,
    );
    await repo.requestPasswordReset('a@b.com');
  });

  test('resendVerification posts the email and password', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning('{"data":{}}', 202, tokens: tokens),
      tokens,
    );
    await repo.resendVerification(email: 'a@b.com', password: 's3cret-pass');
  });

  test('verifyEmail posts the email and code', () async {
    late http.Request sent;
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      ApiClient(
        tokens: tokens,
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"data":{"verified":true}}', 200);
        }),
      ),
      tokens,
    );

    await repo.verifyEmail(email: 'a@b.com', code: '048213');

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/auth/verify-email');
    expect(jsonDecode(sent.body), {'email': 'a@b.com', 'code': '048213'});
    expect(await tokens.read(), isNull, reason: 'verifying signs nobody in');
  });

  test('a refused code surfaces as CODE_INVALID', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(
        '{"error":{"code":"CODE_INVALID","message":"That code is wrong or has expired.","details":[]}}',
        400,
        tokens: tokens,
      ),
      tokens,
    );
    expect(
      () => repo.verifyEmail(email: 'a@b.com', code: '000000'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'CODE_INVALID'),
      ),
    );
  });

  test('resetPassword posts the email, code and new password', () async {
    late http.Request sent;
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      ApiClient(
        tokens: tokens,
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"data":{"reset":true}}', 200);
        }),
      ),
      tokens,
    );

    await repo.resetPassword(
      email: 'a@b.com',
      code: '048213',
      password: 'a whole new password',
    );

    expect(sent.url.path, '/api/v1/auth/password-reset');
    expect(jsonDecode(sent.body), {
      'email': 'a@b.com',
      'code': '048213',
      'password': 'a whole new password',
    });
  });

  test('signOut clears the token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final repo = AuthRepository(
      _clientReturning('{"data":{}}', 200, tokens: tokens),
      tokens,
    );
    await repo.signOut();
    expect(await tokens.read(), isNull);
  });

  test('AuthUser.fromJson reads emailVerified', () {
    final user = AuthUser.fromJson({..._userJson, 'emailVerified': true});
    expect(user.emailVerified, isTrue);
  });

  test('AuthUser.fromJson defaults emailVerified to false when absent', () {
    // A missing field must read as "not verified" rather than trusting an
    // older or malformed response — the safe assumption is the stricter one.
    final user = AuthUser.fromJson(_userJson);
    expect(user.emailVerified, isFalse);
  });

  test('AuthUser.fromJson reads hasPassword and hasGoogle', () {
    final user = AuthUser.fromJson({
      ..._userJson,
      'hasPassword': false,
      'hasGoogle': true,
    });
    expect(user.hasPassword, isFalse);
    expect(user.hasGoogle, isTrue);
  });

  test('AuthUser.fromJson treats an older server as a password account', () {
    // A server from before account deletion sends neither field; every
    // account it knows signs in with a password, and none is linked to
    // Google as far as the app can tell.
    final user = AuthUser.fromJson(_userJson);
    expect(user.hasPassword, isTrue);
    expect(user.hasGoogle, isFalse);
  });

  test(
    'changePassword sends both passwords and stores the fresh token',
    () async {
      final tokens = TokenStore(backing: InMemorySecureStore());
      await tokens.write('old-token');
      late http.Request sent;
      final repo = AuthRepository(
        ApiClient(
          tokens: tokens,
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'data': {'token': 'new-token'},
              }),
              200,
            );
          }),
        ),
        tokens,
      );

      await repo.changePassword(
        currentPassword: 'old secret',
        newPassword: 'new secret!',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/auth/password');
      expect(sent.headers['Authorization'], 'Bearer old-token');
      expect(jsonDecode(sent.body), {
        'currentPassword': 'old secret',
        'newPassword': 'new secret!',
      });
      expect(
        await tokens.read(),
        'new-token',
        reason: 'the old token stops working once the password changes',
      );
      expect(await tokens.readRole(), 'trainee');
    },
  );

  test('a refused password change keeps the old token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('old-token');
    final repo = AuthRepository(
      _clientReturning(
        jsonEncode({
          'error': {
            'code': 'WRONG_PASSWORD',
            'message': "That password isn't right.",
          },
        }),
        400,
        tokens: tokens,
      ),
      tokens,
    );

    await expectLater(
      repo.changePassword(currentPassword: 'nope', newPassword: 'new secret!'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'WRONG_PASSWORD'),
      ),
    );
    expect(await tokens.read(), 'old-token');
  });

  test('deleteAccount with a password posts it and accepts a 204', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    late http.Request sent;
    final repo = AuthRepository(
      ApiClient(
        tokens: tokens,
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      ),
      tokens,
    );

    await repo.deleteAccount(password: 'my secret');

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/account/delete');
    expect(sent.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(sent.body), {'password': 'my secret'});
  });

  test('deleteAccount with a Google token posts only the idToken', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    late http.Request sent;
    final repo = AuthRepository(
      ApiClient(
        tokens: tokens,
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      ),
      tokens,
    );

    await repo.deleteAccount(idToken: 'google-id-token');

    expect(jsonDecode(sent.body), {'idToken': 'google-id-token'});
  });

  test('a refused deletion surfaces the server code', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final repo = AuthRepository(
      _clientReturning(
        jsonEncode({
          'error': {
            'code': 'GOOGLE_ACCOUNT_MISMATCH',
            'message': "That Google account isn't the one this account uses.",
          },
        }),
        400,
        tokens: tokens,
      ),
      tokens,
    );

    await expectLater(
      repo.deleteAccount(idToken: 'someone-else'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'GOOGLE_ACCOUNT_MISMATCH',
        ),
      ),
    );
  });
}
