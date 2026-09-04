import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/forgot_password_screen.dart';

// The server answers every request with the same 202, whatever the address,
// so it can never be used to learn who has an account. The client must not
// hand that information back either — this is the string it shows no matter
// what the repository does.
const _confirmation = "If that address has an account, we've sent a link.";

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.onRequestReset});

  final Future<void> Function()? onRequestReset;

  int requestCalls = 0;
  String? lastEmail;

  @override
  Future<void> requestPasswordReset(String email) {
    requestCalls++;
    lastEmail = email;
    return onRequestReset?.call() ?? Future<void>.value();
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
  Future<void> resendVerification({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, FakeAuthRepository repo) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: ForgotPasswordScreen()),
      ),
    );

void main() {
  testWidgets('renders an email field', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email')), findsOneWidget);
  });

  testWidgets('an empty email is rejected without a network call',
      (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(repo.requestCalls, 0,
        reason: 'validation must run before anything is sent');
  });

  testWidgets('shows the confirmation when the request succeeds',
      (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('email')), 'juan@example.com');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(repo.requestCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(find.text(_confirmation), findsOneWidget);
  });

  testWidgets(
      'shows the exact same confirmation when the request throws, never '
      'the server error', (tester) async {
    final repo = FakeAuthRepository(
      onRequestReset: () async => throw const ApiException(
          'NOT_FOUND', 'No account exists for that address.'),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('email')), 'nope@example.com');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(repo.requestCalls, 1);
    expect(find.text(_confirmation), findsOneWidget);
    expect(find.text('No account exists for that address.'), findsNothing,
        reason: 'the client must never reveal what the server refused to say');
  });
}
