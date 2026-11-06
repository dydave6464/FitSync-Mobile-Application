import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/data/google_sign_in_gateway.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/sign_in_screen.dart';

const _googleFailed =
    "Couldn't sign in with Google. Try again, or use your email and password.";

const _user = AuthUser(
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: false,
  isPremium: false,
);

/// Stands in for the plugin, which needs a platform channel and cannot run
/// under `flutter test`.
class FakeGoogleGateway implements GoogleSignInGateway {
  FakeGoogleGateway(this._result);

  final Future<GoogleSignInResult> Function() _result;
  int calls = 0;

  @override
  Future<GoogleSignInResult> signIn() {
    calls++;
    return _result();
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.onGoogle});

  final Future<AuthUser> Function(String idToken)? onGoogle;
  final List<String> googleTokens = [];

  @override
  Future<AuthUser> signInWithGoogle(String idToken) {
    googleTokens.add(idToken);
    return onGoogle!(idToken);
  }

  @override
  Future<AuthUser> login(String email, String password) =>
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
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> resendVerification({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> verifyEmail({required String email, required String code}) =>
      throw UnimplementedError();

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
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

Future<void> _pump(
  WidgetTester tester, {
  required FakeGoogleGateway gateway,
  required FakeAuthRepository repo,
  List<AuthUser>? seen,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        googleSignInGatewayProvider.overrideWithValue(gateway),
        authRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(
          () => RecordingAuthController(seen ?? []),
        ),
      ],
      child: const MaterialApp(home: SignInScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Runs [body] with `debugPrint` captured rather than printed: a failed
/// Google sign-in logs its cause. Restored inside the test, as flutter_test
/// requires.
Future<List<String?>> _capturingLogs(Future<void> Function() body) async {
  final logs = <String?>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message);
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return logs;
}

void main() {
  testWidgets('a successful Google sign-in posts its id token', (tester) async {
    final seen = <AuthUser>[];
    final gateway = FakeGoogleGateway(
      () async => const GoogleSignInToken('google-id-token'),
    );
    final repo = FakeAuthRepository(onGoogle: (_) async => _user);

    await _pump(tester, gateway: gateway, repo: repo, seen: seen);
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();

    expect(repo.googleTokens, ['google-id-token']);
    expect(seen.single.email, 'juan@example.com');
  });

  testWidgets('cancelling the Google dialog is not an error', (tester) async {
    // The case people forget. A cancelled sign-in is a decision, not a
    // failure, and showing an error for it is wrong.
    final gateway = FakeGoogleGateway(
      () async => const GoogleSignInCancelled(),
    );
    final repo = FakeAuthRepository();

    await _pump(tester, gateway: gateway, repo: repo);
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsNothing);
    expect(
      repo.googleTokens,
      isEmpty,
      reason: 'nothing should be sent when there is no token',
    );

    // Still usable: the user can try again.
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();
    expect(gateway.calls, 2);
  });

  testWidgets('INVALID_GOOGLE_TOKEN shows the server message', (tester) async {
    final gateway = FakeGoogleGateway(
      () async => const GoogleSignInToken('stale-token'),
    );
    final repo = FakeAuthRepository(
      onGoogle: (_) async => throw const ApiException(
        'INVALID_GOOGLE_TOKEN',
        'That Google sign-in could not be verified.',
      ),
    );

    await _pump(tester, gateway: gateway, repo: repo);
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();

    expect(
      find.text('That Google sign-in could not be verified.'),
      findsOneWidget,
    );
  });

  testWidgets('a Google sign-in that cannot reach the server says so plainly', (
    tester,
  ) async {
    final gateway = FakeGoogleGateway(
      () async => const GoogleSignInToken('token'),
    );
    final repo = FakeAuthRepository(
      onGoogle: (_) async => throw const ApiException(
        'NETWORK_ERROR',
        'Could not reach http://10.0.2.2:3000. Check the server is running, '
            'and that "adb reverse tcp:3000 tcp:3000" has been run.',
      ),
    );

    await _pump(tester, gateway: gateway, repo: repo);
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't reach FitSync. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.textContaining('adb'), findsNothing);
  });

  testWidgets('a failed Google sign-in says so, with another way in', (
    tester,
  ) async {
    final gateway = FakeGoogleGateway(
      () async => GoogleSignInFailed(StateError('no token')),
    );
    final repo = FakeAuthRepository();

    await _capturingLogs(() async {
      await _pump(tester, gateway: gateway, repo: repo);
      await tester.tap(find.byKey(const Key('google')));
      await tester.pumpAndSettle();

      expect(find.text(_googleFailed), findsOneWidget);
      expect(repo.googleTokens, isEmpty);

      // Still usable: the user can try again.
      await tester.ensureVisible(find.byKey(const Key('google')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('google')));
      await tester.pumpAndSettle();
    });
    expect(gateway.calls, 2);
  });

  testWidgets('a Google-side error says so, with another way in', (
    tester,
  ) async {
    // No Play Services, a network drop mid-auth, a misconfigured build: the
    // plugin throws something that is not the server's ApiException.
    final gateway = FakeGoogleGateway(
      () async => throw PlatformException(code: 'sign_in_failed'),
    );
    final repo = FakeAuthRepository();

    await _capturingLogs(() async {
      await _pump(tester, gateway: gateway, repo: repo);
      await tester.tap(find.byKey(const Key('google')));
      await tester.pumpAndSettle();
    });

    expect(tester.takeException(), isNull);
    expect(find.text(_googleFailed), findsOneWidget);
    expect(repo.googleTokens, isEmpty);
  });

  testWidgets('the Google button is live, not a coming-soon stub', (
    tester,
  ) async {
    final gateway = FakeGoogleGateway(
      () async => const GoogleSignInCancelled(),
    );
    await _pump(tester, gateway: gateway, repo: FakeAuthRepository());

    expect(find.textContaining('coming soon'), findsNothing);
    expect(
      tester.widget<FsButton>(find.byKey(const Key('google'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('only the Google button spins while Google signs in', (
    tester,
  ) async {
    // AO-18: the email Sign in button used to spin, and be announced as
    // "Sign in, loading", while Google was the one at work.
    final pending = Completer<GoogleSignInResult>();
    final gateway = FakeGoogleGateway(() => pending.future);
    await _pump(tester, gateway: gateway, repo: FakeAuthRepository());

    await tester.tap(find.byKey(const Key('google')));
    await tester.pump();

    final submit = tester.widget<FsButton>(find.byKey(const Key('submit')));
    final google = tester.widget<FsButton>(find.byKey(const Key('google')));
    expect(google.busy, isTrue);
    expect(submit.busy, isFalse);
    expect(submit.onPressed, isNull, reason: 'still one request at a time');

    pending.complete(const GoogleSignInCancelled());
    await tester.pumpAndSettle();
  });

  group('a failed Google sign-in is logged for debugging', () {
    Future<List<String?>> logsOf(
      WidgetTester tester,
      Future<GoogleSignInResult> Function() result,
    ) => _capturingLogs(() async {
      await _pump(
        tester,
        gateway: FakeGoogleGateway(result),
        repo: FakeAuthRepository(),
      );
      await tester.tap(find.byKey(const Key('google')));
      await tester.pumpAndSettle();
    });

    testWidgets('with the cause Google gave', (tester) async {
      final logs = await logsOf(
        tester,
        () async => GoogleSignInFailed(StateError('no id token')),
      );

      expect(logs.where((l) => l!.contains('no id token')), hasLength(1));
      expect(find.text(_googleFailed), findsOneWidget);
    });

    testWidgets('with whatever else went wrong', (tester) async {
      final logs = await logsOf(
        tester,
        () async => throw PlatformException(code: 'sign_in_failed'),
      );

      expect(logs.where((l) => l!.contains('sign_in_failed')), hasLength(1));
    });
  });
}
