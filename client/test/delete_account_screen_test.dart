import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/data/google_sign_in_gateway.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/sign_in_screen.dart';
import 'package:fitsync/features/settings/presentation/delete_account_screen.dart';

import 'helpers/dialog_buttons.dart';

/// Records every deletion asked for; [onDelete] decides how each one ends.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.onDelete});

  final Future<void> Function()? onDelete;
  final List<({String? password, String? idToken})> deletes = [];

  @override
  Future<void> deleteAccount({String? password, String? idToken}) async {
    deletes.add((password: password, idToken: idToken));
    if (onDelete != null) await onDelete!();
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();
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
  Future<AuthUser> signInWithGoogle(String idToken) =>
      throw UnimplementedError();
  @override
  Future<AuthUser> me() => throw UnimplementedError();
  @override
  Future<void> signOut() async {}
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

class _FakeGoogle implements GoogleSignInGateway {
  _FakeGoogle(this.result);

  GoogleSignInResult result;
  int calls = 0;

  @override
  Future<GoogleSignInResult> signIn() async {
    calls++;
    return result;
  }
}

/// Signed in until the account is deleted; the clean-up itself is the
/// controller's own and tested there.
class _AuthController extends AuthController {
  int deletions = 0;

  @override
  Future<AuthState> build() async => const AuthState(
    AuthStatus.ready,
    AuthUser(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: true,
      isPremium: false,
    ),
  );

  @override
  Future<void> onAccountDeleted() async {
    deletions++;
    state = const AsyncData(
      AuthState(AuthStatus.signedOut, null, SignOutReason.accountDeleted),
    );
  }
}

late _AuthController _controller;

/// A small shell like the app's: sign-in once signed out, otherwise a
/// launcher that pushes the screen, so a test can see the pushed route go.
Future<void> _pump(
  WidgetTester tester, {
  required _FakeAuthRepository repo,
  bool hasPassword = true,
  _FakeGoogle? google,
  bool dark = false,
  double textScale = 1.0,
}) async {
  _controller = _AuthController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => _controller),
        googleSignInGatewayProvider.overrideWithValue(
          google ?? _FakeGoogle(const GoogleSignInCancelled()),
        ),
      ],
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) {
            final status = ref.watch(authControllerProvider).value?.status;
            if (status == AuthStatus.signedOut) return const SignInScreen();
            return Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DeleteAccountScreen(hasPassword: hasPassword),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _deleteWithPassword(WidgetTester tester, String password) async {
  await tester.enterText(
    find.byKey(const Key('deleteAccount.password')),
    password,
  );
  await tester.pump();
  await _tapKey(tester, 'deleteAccount.submit');
}

bool _isLive(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isLiveRegion;

void main() {
  testWidgets('says what is deleted and that it cannot be undone', (
    tester,
  ) async {
    await _pump(tester, repo: _FakeAuthRepository());

    expect(find.text('Delete account'), findsOneWidget);
    expect(find.textContaining('workouts'), findsWidgets);
    expect(find.textContaining('meals'), findsWidgets);
    expect(find.text("This can't be undone."), findsOneWidget);
    final button = tester.widget<FsButton>(
      find.byKey(const Key('deleteAccount.submit')),
    );
    expect(button.label, 'Delete my account');
    expect(button.danger, isTrue);
    expect(
      tester.getSize(find.byKey(const Key('deleteAccount.submit'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('a password account confirms with its password', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: _FakeAuthRepository());

    final field = find.byKey(const Key('deleteAccount.password'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    expect(tester.getSemantics(field).label, contains('Password'));
    expect(find.byKey(const Key('deleteAccount.google')), findsNothing);
    final toggle = find.byKey(const Key('deleteAccount.password.reveal'));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<TextField>(field).obscureText, isFalse);
    handle.dispose();
  });

  testWidgets('an empty password is asked for before anything else', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo: repo);
    await _tapKey(tester, 'deleteAccount.submit');

    expect(find.text('Enter your password.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.deletes, isEmpty);
  });

  testWidgets('the last dialog asks once more; Keep account keeps it', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo: repo);
    await _deleteWithPassword(tester, 'my secret');

    expect(find.text('Delete your account?'), findsOneWidget);
    final keep = dialogButton('Keep account');
    final delete = dialogButton('Delete');
    expect(keep, findsOneWidget);
    expect(delete, findsOneWidget);
    expect(labelColor(tester, delete), dialogRed(tester));
    expect(labelColor(tester, keep), isNot(dialogRed(tester)));

    await tester.tap(keep);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.deletes, isEmpty);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  });

  testWidgets('Delete sends the password, signs out and says why', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo: repo);
    await _deleteWithPassword(tester, 'my secret');
    await tester.tap(dialogButton('Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletes, [(password: 'my secret', idToken: null)]);
    expect(_controller.deletions, 1);
    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Your account was deleted.'), findsOneWidget);
  });

  testWidgets('a wrong password is said under the password field', (
    tester,
  ) async {
    final repo = _FakeAuthRepository(
      onDelete: () async => throw const ApiException(
        'WRONG_PASSWORD',
        "That password isn't right.",
      ),
    );
    await _pump(tester, repo: repo);
    await _deleteWithPassword(tester, 'wrong');
    await tester.tap(dialogButton('Delete'));
    await tester.pumpAndSettle();

    final message = find.text("That password isn't right.");
    expect(message, findsOneWidget);
    expect(
      tester.getRect(message).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const Key('deleteAccount.password'))).bottom,
      ),
    );
    expect(find.byKey(const Key('deleteAccount.error')), findsNothing);
    expect(_controller.deletions, 0);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  });

  testWidgets('any other failure is a live error line in plain words', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repo = _FakeAuthRepository(
      onDelete: () async => throw const ApiException('NETWORK_ERROR', 'raw'),
    );
    await _pump(tester, repo: repo);
    await _deleteWithPassword(tester, 'my secret');
    await tester.tap(dialogButton('Delete'));
    await tester.pumpAndSettle();

    final line = find.byKey(const Key('deleteAccount.error'));
    expect(
      tester.widget<FsErrorLine>(line).message,
      userMessage(const ApiException('NETWORK_ERROR', 'raw')),
    );
    expect(_isLive(tester, line), isTrue);
    expect(_controller.deletions, 0);
    handle.dispose();
  });

  testWidgets('a Google account confirms with Google, then deletes', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    final google = _FakeGoogle(const GoogleSignInToken('fresh-id-token'));
    await _pump(tester, repo: repo, hasPassword: false, google: google);

    expect(find.byKey(const Key('deleteAccount.password')), findsNothing);
    final confirm = find.byKey(const Key('deleteAccount.google'));
    expect(tester.widget<FsButton>(confirm).label, 'Confirm with Google');

    await _tapKey(tester, 'deleteAccount.google');
    expect(google.calls, 1);
    expect(find.text('Confirmed with Google.'), findsOneWidget);

    await _tapKey(tester, 'deleteAccount.submit');
    await tester.tap(dialogButton('Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletes, [(password: null, idToken: 'fresh-id-token')]);
    expect(find.text('Your account was deleted.'), findsOneWidget);
  });

  testWidgets('a Google account must confirm before Delete goes on', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo: repo, hasPassword: false);
    await _tapKey(tester, 'deleteAccount.submit');

    expect(find.text('Confirm with Google first.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.deletes, isEmpty);
  });

  testWidgets('closing the Google picker changes nothing', (tester) async {
    final google = _FakeGoogle(const GoogleSignInCancelled());
    await _pump(
      tester,
      repo: _FakeAuthRepository(),
      hasPassword: false,
      google: google,
    );
    await _tapKey(tester, 'deleteAccount.google');

    expect(google.calls, 1);
    expect(find.byType(FsErrorLine), findsNothing);
    expect(find.text('Confirmed with Google.'), findsNothing);
  });

  testWidgets('a Google failure says so', (tester) async {
    await _pump(
      tester,
      repo: _FakeAuthRepository(),
      hasPassword: false,
      google: _FakeGoogle(GoogleSignInFailed(StateError('no play services'))),
    );
    // The cause is logged in debug builds; kept out of the test output.
    final logs = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    try {
      await _tapKey(tester, 'deleteAccount.google');
    } finally {
      debugPrint = original;
    }

    expect(logs.single, contains('no play services'));
    expect(
      find.text("Couldn't confirm with Google. Try again."),
      findsOneWidget,
    );
  });

  testWidgets('a different Google account is named, and must confirm again', (
    tester,
  ) async {
    final repo = _FakeAuthRepository(
      onDelete: () async =>
          throw const ApiException('GOOGLE_ACCOUNT_MISMATCH', 'server words'),
    );
    await _pump(
      tester,
      repo: repo,
      hasPassword: false,
      google: _FakeGoogle(const GoogleSignInToken('other-account')),
    );
    await _tapKey(tester, 'deleteAccount.google');
    await _tapKey(tester, 'deleteAccount.submit');
    await tester.tap(dialogButton('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text("That Google account isn't the one this account uses."),
      findsOneWidget,
    );
    expect(
      find.text('Confirmed with Google.'),
      findsNothing,
      reason: 'that confirmation was for the wrong account',
    );
    expect(_controller.deletions, 0);
  });

  for (final dark in [false, true]) {
    for (final hasPassword in [true, false]) {
      testWidgets('fits 320 dp at 2x text (${dark ? 'dark' : 'light'}, '
          '${hasPassword ? 'password' : 'Google'})', (tester) async {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          repo: _FakeAuthRepository(
            onDelete: () async =>
                throw const ApiException('NETWORK_ERROR', 'raw'),
          ),
          hasPassword: hasPassword,
          google: _FakeGoogle(const GoogleSignInToken('t')),
          dark: dark,
          textScale: 2.0,
        );
        expect(tester.takeException(), isNull);

        if (hasPassword) {
          await _deleteWithPassword(tester, 'my secret');
        } else {
          await _tapKey(tester, 'deleteAccount.google');
          await _tapKey(tester, 'deleteAccount.submit');
        }
        expect(tester.takeException(), isNull);
        await tester.tap(dialogButton('Delete'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('deleteAccount.error')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
