import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/check_email_screen.dart';
import 'package:fitsync/features/auth/presentation/forgot_password_screen.dart';
import 'package:fitsync/features/auth/presentation/sign_in_screen.dart';

AuthUser _user() => const AuthUser(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: false,
      isPremium: false,
    );

/// Records what the screen asked for, so a test can assert that a request was
/// never made as well as that one was.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.onLogin, this.onRegister});

  final Future<AuthUser> Function()? onLogin;
  final Future<void> Function()? onRegister;

  int loginCalls = 0;
  int registerCalls = 0;
  String? lastEmail;
  String? lastFullName;

  @override
  Future<AuthUser> login(String email, String password) {
    loginCalls++;
    lastEmail = email;
    return onLogin!();
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) {
    registerCalls++;
    lastEmail = email;
    lastFullName = fullName;
    return onRegister!();
  }

  @override
  Future<AuthUser> me() => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<AuthUser> signInWithGoogle(String idToken) =>
      throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> resendVerification({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();
}

class RecordingAuthController extends AuthController {
  RecordingAuthController(this.seen);

  final List<AuthUser> seen;

  @override
  Future<AuthState> build() async => AuthState.signedOut;

  @override
  void onAuthenticated(AuthUser user) {
    seen.add(user);
    super.onAuthenticated(user);
  }
}

Future<void> _pump(
  WidgetTester tester,
  FakeAuthRepository repo, {
  List<AuthUser>? seen,
}) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          authControllerProvider
              .overrideWith(() => RecordingAuthController(seen ?? [])),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

Future<void> _fillAndSubmit(
  WidgetTester tester, {
  String email = 'juan@example.com',
  String password = 's3cret-pass',
}) async {
  await tester.enterText(find.byKey(const Key('email')), email);
  await tester.enterText(find.byKey(const Key('password')), password);
  await tester.tap(find.byKey(const Key('submit')));
}

void main() {
  testWidgets('renders an email and a password field', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email')), findsOneWidget);
    expect(find.byKey(const Key('password')), findsOneWidget);
  });

  testWidgets('an empty email is rejected without a network call',
      (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(repo.loginCalls, 0,
        reason: 'validation must run before anything is sent');
  });

  testWidgets('a successful login hands the user to the controller',
      (tester) async {
    final seen = <AuthUser>[];
    final repo = FakeAuthRepository(onLogin: () async => _user());
    await _pump(tester, repo, seen: seen);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(repo.loginCalls, 1);
    expect(seen.single.email, 'juan@example.com');
  });

  testWidgets('INVALID_CREDENTIALS shows the message and keeps the input',
      (tester) async {
    final repo = FakeAuthRepository(
      onLogin: () async => throw const ApiException(
          'INVALID_CREDENTIALS', 'Email or password is incorrect.'),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('email'))).controller!.text,
      'juan@example.com',
      reason: 'retyping the whole email to fix one character is needless',
    );
  });

  testWidgets('EMAIL_TAKEN on register shows the message', (tester) async {
    final repo = FakeAuthRepository(
      onRegister: () async => throw const ApiException(
          'EMAIL_TAKEN', 'That email is already registered.'),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggleMode')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('fullName')), 'Juan Dela Cruz');
    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(repo.registerCalls, 1);
    expect(find.text('That email is already registered.'), findsOneWidget);
  });

  testWidgets('a NETWORK_ERROR shows its retryable message', (tester) async {
    final repo = FakeAuthRepository(
      onLogin: () async => throw const ApiException(
          'NETWORK_ERROR', 'Could not reach the server.'),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);
  });

  testWidgets('a double tap on register cannot create two accounts',
      (tester) async {
    final pending = Completer<void>();
    final repo = FakeAuthRepository(onRegister: () => pending.future);
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggleMode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fullName')), 'Juan Dela Cruz');

    await _fillAndSubmit(tester);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(repo.registerCalls, 1,
        reason: 'the button must be disabled while a request is in flight');

    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a successful registration shows the check-your-email screen',
      (tester) async {
    final seen = <AuthUser>[];
    final repo = FakeAuthRepository(onRegister: () async {});
    await _pump(tester, repo, seen: seen);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggleMode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fullName')), 'Juan Dela Cruz');
    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byType(CheckEmailScreen), findsOneWidget,
        reason: 'there is no token yet, so onboarding must not start');
    expect(seen, isEmpty,
        reason: 'a registration with no session must never reach the controller');
  });

  testWidgets('EMAIL_NOT_VERIFIED on login shows the check-your-email screen',
      (tester) async {
    final repo = FakeAuthRepository(
      onLogin: () async => throw const ApiException(
          'EMAIL_NOT_VERIFIED', 'Verify your email before signing in.'),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byType(CheckEmailScreen), findsOneWidget,
        reason: 'the way forward should be obvious, not a generic error');
    expect(find.text('Verify your email before signing in.'), findsNothing);
  });

  testWidgets('Forgot password? opens the reset screen', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('forgotPassword')));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('Forgot password? is hidden while registering', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggleMode')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgotPassword')), findsNothing);
  });
}
