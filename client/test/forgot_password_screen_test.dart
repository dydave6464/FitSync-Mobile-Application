import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/code_entry.dart';
import 'package:fitsync/features/auth/presentation/forgot_password_screen.dart';

/// Shown whatever the repository does: the server answers every request the
/// same way so it can never reveal who has an account, and the app must not
/// hand that back either.
const _sent = "If that address has an account, we've sent a code.";
const _resent = 'If that address has an account, a new code is on its way.';

const _user = AuthUser(
  userId: 1,
  email: 'juan@example.com',
  fullName: 'Juan',
  onboardingCompleted: true,
  isPremium: false,
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.onRequestReset, this.onReset, this.onLogin});

  final Future<void> Function()? onRequestReset;
  final Future<void> Function()? onReset;
  final Future<AuthUser> Function()? onLogin;

  int requestCalls = 0;
  int resetCalls = 0;
  int loginCalls = 0;
  String? lastEmail;
  String? lastCode;
  String? lastPassword;

  @override
  Future<void> requestPasswordReset(String email) {
    requestCalls++;
    lastEmail = email;
    return onRequestReset?.call() ?? Future<void>.value();
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) {
    resetCalls++;
    lastEmail = email;
    lastCode = code;
    lastPassword = password;
    return onReset?.call() ?? Future<void>.value();
  }

  @override
  Future<AuthUser> login(String email, String password) {
    loginCalls++;
    lastEmail = email;
    lastPassword = password;
    return onLogin?.call() ?? Future.value(_user);
  }

  @override
  Future<void> verifyEmail({required String email, required String code}) =>
      throw UnimplementedError();

  @override
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();
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

Future<List<AuthUser>> _pump(
  WidgetTester tester,
  FakeAuthRepository repo,
) async {
  final seen = <AuthUser>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(
          () => RecordingAuthController(seen),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ForgotPasswordScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return seen;
}

Future<void> _sendCode(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('email')), 'juan@example.com');
  await tester.tap(find.byKey(const Key('submit')));
  await tester.pumpAndSettle();
}

Future<void> _fillReset(
  WidgetTester tester, {
  String code = '048213',
  String password = 'a whole new password',
}) async {
  await tester.enterText(find.byKey(const Key('code')), code);
  await tester.enterText(find.byKey(const Key('newPassword')), password);
  await tester.tap(find.byKey(const Key('reset')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty email is rejected without a network call', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(repo.requestCalls, 0);
  });

  testWidgets('sending the code moves to the code step', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await _sendCode(tester);

    expect(repo.requestCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(find.text(_sent), findsOneWidget);
    expect(find.byKey(const Key('code')), findsOneWidget);
    expect(find.byKey(const Key('newPassword')), findsOneWidget);
  });

  testWidgets(
    'a failed request looks exactly the same, never the server error',
    (tester) async {
      final repo = FakeAuthRepository(
        onRequestReset: () async => throw const ApiException(
          'NOT_FOUND',
          'No account exists for that address.',
        ),
      );
      await _pump(tester, repo);

      await _sendCode(tester);

      expect(find.text(_sent), findsOneWidget);
      expect(find.byKey(const Key('code')), findsOneWidget);
      expect(find.text('No account exists for that address.'), findsNothing);
    },
  );

  testWidgets('a right code resets, signs in and closes the screen', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    final seen = await _pump(tester, repo);

    await _sendCode(tester);
    await _fillReset(tester);

    expect(repo.resetCalls, 1);
    expect(repo.lastCode, '048213');
    expect(repo.loginCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(repo.lastPassword, 'a whole new password');
    expect(seen, [_user]);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });

  testWidgets('a short password is refused before anything is sent', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await _sendCode(tester);
    await _fillReset(tester, password: 'short');

    expect(
      find.text('Use at least 8 characters for your new password.'),
      findsOneWidget,
    );
    expect(repo.resetCalls, 0);
  });

  testWidgets('a wrong code says so and signs nobody in', (tester) async {
    final repo = FakeAuthRepository(
      onReset: () async => throw const ApiException(
        'CODE_INVALID',
        'That code is wrong or has expired.',
      ),
      // The password was not changed, so the one sign-in a CODE_INVALID
      // triggers (see the lost-response test) is refused.
      onLogin: () async => throw const ApiException(
        'INVALID_CREDENTIALS',
        'Email or password is incorrect.',
      ),
    );
    final seen = await _pump(tester, repo);

    await _sendCode(tester);
    await _fillReset(tester, code: '000000');

    expect(find.text(wrongCodeMessage), findsOneWidget);
    expect(repo.loginCalls, 1, reason: 'one check for a lost reply, no more');
    expect(seen, isEmpty);
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('a lost reset response still signs in', (tester) async {
    // The server reset the password but its reply was lost; the retry is told
    // CODE_INVALID for a code this very reset already spent.
    final repo = FakeAuthRepository(
      onReset: () async => throw const ApiException(
        'CODE_INVALID',
        'That code is wrong or has expired.',
      ),
    );
    final seen = await _pump(tester, repo);

    await _sendCode(tester);
    await _fillReset(tester);

    expect(repo.resetCalls, 1);
    expect(repo.loginCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(repo.lastPassword, 'a whole new password', reason: 'the new one');
    expect(seen, [_user]);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });

  testWidgets('reset but the sign-in failed: the button retries sign-in only', (
    tester,
  ) async {
    var failLogin = true;
    final repo = FakeAuthRepository(
      onLogin: () async {
        if (failLogin) {
          throw const ApiException('NETWORK_ERROR', 'Could not reach.');
        }
        return _user;
      },
    );
    final seen = await _pump(tester, repo);

    await _sendCode(tester);
    await _fillReset(tester);

    expect(
      find.text('Your password is reset. Tap to sign in.'),
      findsOneWidget,
    );

    failLogin = false;
    await tester.tap(find.byKey(const Key('reset')));
    await tester.pumpAndSettle();

    expect(repo.resetCalls, 1, reason: 'the spent code is not sent again');
    expect(repo.loginCalls, 2);
    expect(seen, [_user]);
  });

  testWidgets('Send a new code asks again', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await _sendCode(tester);
    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    expect(repo.requestCalls, 2);
    expect(find.text(_resent), findsOneWidget);
  });
}
