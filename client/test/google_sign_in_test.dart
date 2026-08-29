import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/data/google_sign_in_gateway.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/sign_in_screen.dart';

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

  final Future<String?> Function() _result;
  int calls = 0;

  @override
  Future<String?> idToken() {
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
  Future<AuthUser> register({
    required String email,
    required String password,
    required String fullName,
  }) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> me() => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
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
  await tester.pumpWidget(ProviderScope(
    overrides: [
      googleSignInGatewayProvider.overrideWithValue(gateway),
      authRepositoryProvider.overrideWithValue(repo),
      authControllerProvider
          .overrideWith(() => RecordingAuthController(seen ?? [])),
    ],
    child: const MaterialApp(home: SignInScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a successful Google sign-in posts its id token', (tester) async {
    final seen = <AuthUser>[];
    final gateway = FakeGoogleGateway(() async => 'google-id-token');
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
    final gateway = FakeGoogleGateway(() async => null);
    final repo = FakeAuthRepository();

    await _pump(tester, gateway: gateway, repo: repo);
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsNothing);
    expect(repo.googleTokens, isEmpty,
        reason: 'nothing should be sent when there is no token');

    // Still usable: the user can try again.
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();
    expect(gateway.calls, 2);
  });

  testWidgets('INVALID_GOOGLE_TOKEN shows the server message', (tester) async {
    final gateway = FakeGoogleGateway(() async => 'stale-token');
    final repo = FakeAuthRepository(
      onGoogle: (_) async => throw const ApiException(
          'INVALID_GOOGLE_TOKEN', 'That Google sign-in could not be verified.'),
    );

    await _pump(tester, gateway: gateway, repo: repo);
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();

    expect(find.text('That Google sign-in could not be verified.'),
        findsOneWidget);
  });

  testWidgets('the Google button is live, not a coming-soon stub',
      (tester) async {
    final gateway = FakeGoogleGateway(() async => null);
    await _pump(tester, gateway: gateway, repo: FakeAuthRepository());

    expect(find.textContaining('coming soon'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(const Key('google'))).onPressed,
      isNotNull,
    );
  });
}
