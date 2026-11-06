import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/check_email_screen.dart';
import 'package:fitsync/features/auth/presentation/code_entry.dart';

const _user = AuthUser(
  userId: 1,
  email: 'juan@example.com',
  fullName: 'Juan',
  onboardingCompleted: false,
  isPremium: false,
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.onVerify, this.onLogin, this.onResend});

  final Future<void> Function()? onVerify;
  final Future<AuthUser> Function()? onLogin;
  final Future<void> Function()? onResend;

  int verifyCalls = 0;
  int loginCalls = 0;
  int resendCalls = 0;
  String? lastCode;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> verifyEmail({required String email, required String code}) {
    verifyCalls++;
    lastEmail = email;
    lastCode = code;
    return onVerify?.call() ?? Future<void>.value();
  }

  @override
  Future<AuthUser> login(String email, String password) {
    loginCalls++;
    lastEmail = email;
    lastPassword = password;
    return onLogin?.call() ?? Future.value(_user);
  }

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
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) => throw UnimplementedError();

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
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
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

/// A home screen that pushes CheckEmailScreen, as sign-in does, so a test can
/// see the screen close again.
Future<List<AuthUser>> _pump(
  WidgetTester tester,
  FakeAuthRepository repo, {
  bool sendCodeOnOpen = false,
}) async {
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
                  builder: (_) => CheckEmailScreen(
                    email: 'juan@example.com',
                    password: 's3cret-pass',
                    sendCodeOnOpen: sendCodeOnOpen,
                  ),
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

bool _isLive(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isLiveRegion;

void main() {
  testWidgets('asks for the code sent to the address', (tester) async {
    await _pump(tester, FakeAuthRepository());

    expect(
      find.text('We sent a 6-digit code to juan@example.com. Enter it below.'),
      findsOneWidget,
    );
    expect(find.textContaining('link'), findsNothing);
  });

  testWidgets('the field keeps digits only, at most six', (tester) async {
    await _pump(tester, FakeAuthRepository());

    await tester.enterText(find.byKey(const Key('code')), 'ab 12 34 567');
    final field = tester.widget<TextField>(find.byKey(const Key('code')));
    expect(field.controller!.text, '123456');
  });

  testWidgets('Verify does nothing until six digits are in', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('code')), '12345');
    // A rebuild is needed for the button's enabled state -- computed from
    // the code length at the last build -- to catch up with the text just
    // entered; enterText updates the controller synchronously but does not
    // itself trigger one (see TestTextInput.enterText's own doc comment).
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    expect(repo.verifyCalls, 0);
  });

  testWidgets('a right code verifies, signs in and closes the screen', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    final seen = await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('code')), '048213');
    // See the comment above: the button only becomes enabled once the
    // screen rebuilds with the newly entered code.
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    expect(repo.verifyCalls, 1);
    expect(repo.lastCode, '048213');
    expect(repo.loginCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(repo.lastPassword, 's3cret-pass');
    expect(seen, [_user]);
    expect(find.byType(CheckEmailScreen), findsNothing);
  });

  testWidgets('a right code shows a signed-in banner that then goes away', (
    tester,
  ) async {
    await _pump(tester, FakeAuthRepository());

    await tester.enterText(find.byKey(const Key('code')), '048213');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(SnackBar, "Email verified — you're signed in."),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a wrong code says so and signs nobody in', (tester) async {
    final repo = FakeAuthRepository(
      onVerify: () async => throw const ApiException(
        'CODE_INVALID',
        'That code is wrong or has expired.',
      ),
      // What the server says to a still-unverified account: the one sign-in
      // a CODE_INVALID triggers (see the lost-response test) fails.
      onLogin: () async => throw const ApiException(
        'EMAIL_NOT_VERIFIED',
        'Verify your email before signing in.',
      ),
    );
    final seen = await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('code')), '000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    expect(find.text(wrongCodeMessage), findsOneWidget);
    expect(repo.loginCalls, 1, reason: 'one check for a lost reply, no more');
    expect(seen, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(CheckEmailScreen), findsOneWidget);
  });

  testWidgets('a lost verify response still signs in', (tester) async {
    // The server accepted the code but its reply was lost; the retry is told
    // CODE_INVALID for a code this very account already spent.
    final repo = FakeAuthRepository(
      onVerify: () async => throw const ApiException(
        'CODE_INVALID',
        'That code is wrong or has expired.',
      ),
    );
    final seen = await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('code')), '048213');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    expect(repo.verifyCalls, 1);
    expect(repo.loginCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(repo.lastPassword, 's3cret-pass');
    expect(seen, [_user]);
    expect(find.byType(CheckEmailScreen), findsNothing);
    expect(
      find.widgetWithText(SnackBar, "Email verified — you're signed in."),
      findsOneWidget,
    );
  });

  testWidgets(
    'verified but the sign-in failed: the button retries the sign-in only',
    (tester) async {
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

      await tester.enterText(find.byKey(const Key('code')), '048213');
      await tester.pump();
      await tester.tap(find.byKey(const Key('verify')));
      await tester.pumpAndSettle();

      expect(
        find.text('Your email is verified. Tap to sign in.'),
        findsOneWidget,
      );
      // AO-9: good news, so neutral text rather than a red error line --
      // still said aloud as it appears.
      expect(find.byType(FsErrorLine), findsNothing);
      expect(
        find.ancestor(
          of: find.text('Your email is verified. Tap to sign in.'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsOneWidget);

      failLogin = false;
      await tester.tap(find.byKey(const Key('verify')));
      await tester.pumpAndSettle();

      expect(repo.verifyCalls, 1, reason: 'the spent code is not sent again');
      expect(repo.loginCalls, 2);
      expect(seen, [_user]);
    },
  );

  testWidgets('Send a new code resends with the same credentials', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    expect(repo.resendCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(repo.lastPassword, 's3cret-pass');
    expect(find.text(newCodeMessage), findsOneWidget);
  });

  testWidgets('opened from sign-in, it asks for a fresh code once', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo, sendCodeOnOpen: true);

    expect(repo.resendCalls, 1);
    expect(repo.lastEmail, 'juan@example.com');
    expect(repo.lastPassword, 's3cret-pass');
    expect(find.text(newCodeMessage), findsOneWidget);
  });

  testWidgets('by default it sends no code on open', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    expect(repo.resendCalls, 0, reason: 'registration has just sent one');
    expect(find.text(newCodeMessage), findsNothing);
  });

  testWidgets('a resend failure shows plain words, not the developer text', (
    tester,
  ) async {
    final repo = FakeAuthRepository(
      onResend: () async => throw const ApiException(
        'NETWORK_ERROR',
        'Could not reach http://10.0.2.2:3000. Check the server is running, '
            'and that "adb reverse tcp:3000 tcp:3000" has been run.',
      ),
    );
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't reach FitSync. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.textContaining('adb'), findsNothing);
  });

  testWidgets('a server message on resend still reads as sent', (tester) async {
    final repo = FakeAuthRepository(
      onResend: () async => throw const ApiException(
        'TOO_MANY_REQUESTS',
        'Wait a minute before asking for another code.',
      ),
    );
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    expect(
      find.text('Wait a minute before asking for another code.'),
      findsOneWidget,
    );
  });

  testWidgets('a verify that gets a non-JSON reply shows plain words', (
    tester,
  ) async {
    final repo = FakeAuthRepository(
      onVerify: () async => throw const ApiException(
        'INVALID_RESPONSE',
        'Server returned a non-JSON body (HTTP 502).',
      ),
    );
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('code')), '048213');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong on our side. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('non-JSON'), findsNothing);
  });

  testWidgets('a wrong code is a red error line that is read aloud', (
    tester,
  ) async {
    final repo = FakeAuthRepository(
      onVerify: () async => throw const ApiException(
        'CODE_INVALID',
        'That code is wrong or has expired.',
      ),
      onLogin: () async => throw const ApiException(
        'EMAIL_NOT_VERIFIED',
        'Verify your email before signing in.',
      ),
    );
    final handle = tester.ensureSemantics();
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('code')), '000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    final message = find.text(wrongCodeMessage);
    expect(
      find.ancestor(of: message, matching: find.byType(FsErrorLine)),
      findsOneWidget,
    );
    expect(_isLive(tester, message), isTrue);
    handle.dispose();
  });

  testWidgets('a new code on its way is plain news, still read aloud', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, FakeAuthRepository());

    await tester.tap(find.byKey(const Key('resend')));
    await tester.pumpAndSettle();

    final message = find.text(newCodeMessage);
    expect(message, findsOneWidget);
    expect(
      find.ancestor(of: message, matching: find.byType(FsErrorLine)),
      findsNothing,
      reason: 'a confirmation must not look like an error',
    );
    expect(_isLive(tester, message), isTrue);
    handle.dispose();
  });

  testWidgets('the code field keeps a visible name a screen reader hears', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeAuthRepository());

    expect(find.text('Code'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('code'))).label,
      contains('Code'),
    );
    semantics.dispose();
  });
}
