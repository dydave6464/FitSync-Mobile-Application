import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/check_email_screen.dart';

/// Records what the screen asked for, so a test can assert the right
/// credentials were sent as well as that a call was made at all.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.onResend});

  final Future<void> Function()? onResend;

  int resendCalls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> resendVerification({
    required String email,
    required String password,
  }) {
    resendCalls++;
    lastEmail = email;
    lastPassword = password;
    return onResend?.call() ?? Future<void>.value();
  }

  @override
  Future<AuthUser> login(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> me() => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<AuthUser> signInWithGoogle(String idToken) =>
      throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, FakeAuthRepository repo) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: CheckEmailScreen(
            email: 'juan@example.com',
            password: 's3cret-pass',
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows the address the link was sent to', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(find.textContaining('juan@example.com'), findsOneWidget);
  });

  testWidgets('Resend calls the endpoint with the same credentials',
      (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    expect(repo.resendCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(repo.lastPassword, 's3cret-pass');
  });

  testWidgets('a resend failure surfaces the server message', (tester) async {
    final repo = FakeAuthRepository(
      onResend: () async => throw const ApiException(
          'NETWORK_ERROR', 'Could not reach the server.'),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);
  });
}
