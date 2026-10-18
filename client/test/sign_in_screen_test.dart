import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
  int resendCalls = 0;
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

  /// Answered, not thrown: CheckEmailScreen opened from sign-in asks for a
  /// fresh code as soon as it appears.
  @override
  Future<void> resendVerification({
    required String email,
    required String password,
  }) {
    resendCalls++;
    return Future<void>.value();
  }

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
  WidgetTester tester,
  FakeAuthRepository repo, {
  List<AuthUser>? seen,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        () => RecordingAuthController(seen ?? []),
      ),
    ],
    child: const MaterialApp(home: SignInScreen()),
  ),
);

/// The narrowest phone the app supports at the largest text it is tested
/// with, so a test can prove nothing on the form overflows there.
Future<void> _pumpSmallLargeText(WidgetTester tester, FakeAuthRepository repo) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => RecordingAuthController([])),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: const SignInScreen(),
      ),
    ),
  );
}

/// Scrolls to a control before tapping it: with labels on every field the
/// sign-up form is taller than the default test screen.
Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
}

Future<void> _toRegister(WidgetTester tester) async {
  await _tapKey(tester, 'toggleMode');
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key)));

Future<void> _fillAndSubmit(
  WidgetTester tester, {
  String email = 'juan@example.com',
  String password = 's3cret-pass',
}) async {
  await tester.enterText(find.byKey(const Key('email')), email);
  await tester.enterText(find.byKey(const Key('password')), password);
  await _tapKey(tester, 'submit');
}

void main() {
  testWidgets('renders an email and a password field', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email')), findsOneWidget);
    expect(find.byKey(const Key('password')), findsOneWidget);
  });

  testWidgets('an empty email is rejected without a network call', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _tapKey(tester, 'submit');
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(
      repo.loginCalls,
      0,
      reason: 'validation must run before anything is sent',
    );
  });

  testWidgets('a successful login hands the user to the controller', (
    tester,
  ) async {
    final seen = <AuthUser>[];
    final repo = FakeAuthRepository(onLogin: () async => _user());
    await _pump(tester, repo, seen: seen);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(repo.loginCalls, 1);
    expect(seen.single.email, 'juan@example.com');
  });

  testWidgets('INVALID_CREDENTIALS shows the message and keeps the input', (
    tester,
  ) async {
    final repo = FakeAuthRepository(
      onLogin: () async => throw const ApiException(
        'INVALID_CREDENTIALS',
        'Email or password is incorrect.',
      ),
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
        'EMAIL_TAKEN',
        'That email is already registered.',
      ),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _toRegister(tester);

    await tester.enterText(find.byKey(const Key('fullName')), 'Juan Dela Cruz');
    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(repo.registerCalls, 1);
    expect(find.text('That email is already registered.'), findsOneWidget);
  });

  testWidgets('a NETWORK_ERROR shows its retryable message', (tester) async {
    final repo = FakeAuthRepository(
      onLogin: () async => throw const ApiException(
        'NETWORK_ERROR',
        'Could not reach the server.',
      ),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);
  });

  testWidgets('a double tap on register cannot create two accounts', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repo = FakeAuthRepository(onRegister: () => pending.future);
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _toRegister(tester);
    await tester.enterText(find.byKey(const Key('fullName')), 'Juan Dela Cruz');

    await _fillAndSubmit(tester);
    await tester.pump();
    // A plain tap: the first one already scrolled the button into view, and
    // settling would wait forever on the busy spinner.
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(
      repo.registerCalls,
      1,
      reason: 'the button must be disabled while a request is in flight',
    );

    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a successful registration shows the check-your-email screen', (
    tester,
  ) async {
    final seen = <AuthUser>[];
    final repo = FakeAuthRepository(onRegister: () async {});
    await _pump(tester, repo, seen: seen);
    await tester.pumpAndSettle();

    await _toRegister(tester);
    await tester.enterText(find.byKey(const Key('fullName')), 'Juan Dela Cruz');
    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(
      find.byType(CheckEmailScreen),
      findsOneWidget,
      reason: 'there is no token yet, so onboarding must not start',
    );
    expect(
      seen,
      isEmpty,
      reason: 'a registration with no session must never reach the controller',
    );
    expect(
      tester
          .widget<CheckEmailScreen>(find.byType(CheckEmailScreen))
          .sendCodeOnOpen,
      isFalse,
      reason: 'registration has just sent a code',
    );
    expect(repo.resendCalls, 0);
  });

  testWidgets('EMAIL_NOT_VERIFIED on login shows the check-your-email screen', (
    tester,
  ) async {
    final repo = FakeAuthRepository(
      onLogin: () async => throw const ApiException(
        'EMAIL_NOT_VERIFIED',
        'Verify your email before signing in.',
      ),
    );
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(
      find.byType(CheckEmailScreen),
      findsOneWidget,
      reason: 'the way forward should be obvious, not a generic error',
    );
    expect(find.text('Verify your email before signing in.'), findsNothing);
    expect(
      tester
          .widget<CheckEmailScreen>(find.byType(CheckEmailScreen))
          .sendCodeOnOpen,
      isTrue,
      reason: 'the code on file has most likely expired by now',
    );
    expect(repo.resendCalls, 1);
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

    await _toRegister(tester);

    expect(find.byKey(const Key('forgotPassword')), findsNothing);
  });

  testWidgets('every field has a visible label on sign in and sign up', (
    tester,
  ) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Full name'), findsNothing);

    await _toRegister(tester);

    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('a screen reader hears each label on its field', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();
    await _toRegister(tester);

    for (final (key, label) in [
      ('fullName', 'Full name'),
      ('email', 'Email'),
      ('password', 'Password'),
    ]) {
      expect(
        tester.getSemantics(find.byKey(Key(key))).label,
        contains(label),
        reason: 'the $key field must be announced by its label',
      );
    }
    semantics.dispose();
  });

  testWidgets('autofill hints match the mode', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(_field(tester, 'email').autofillHints, [AutofillHints.email]);
    expect(_field(tester, 'password').autofillHints, [AutofillHints.password]);

    await _toRegister(tester);

    expect(_field(tester, 'fullName').autofillHints, [AutofillHints.name]);
    expect(_field(tester, 'email').autofillHints, [AutofillHints.email]);
    expect(
      _field(tester, 'password').autofillHints,
      [AutofillHints.newPassword],
      reason: 'a new password lets the manager offer a strong one and save it',
    );
  });

  testWidgets('the eye button shows and hides the password', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(_field(tester, 'password').obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('togglePassword'))),
      greaterThanOrEqualTo(const Size(48, 48)),
    );

    await tester.tap(find.byKey(const Key('togglePassword')));
    await tester.pumpAndSettle();

    expect(_field(tester, 'password').obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsNothing);

    await tester.tap(find.byKey(const Key('togglePassword')));
    await tester.pumpAndSettle();

    expect(_field(tester, 'password').obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  // Both links were only as tall as their small text, about 16dp.
  testWidgets('the text links take a 48dp tap', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    for (final key in ['forgotPassword', 'toggleMode']) {
      final link = tester.getRect(find.byKey(Key(key)));
      expect(link.height, greaterThanOrEqualTo(48), reason: key);
      expect(link.width, greaterThanOrEqualTo(48), reason: key);
    }

    // A tap near the link's top edge, above the words, still switches mode.
    await tester.ensureVisible(find.byKey(const Key('toggleMode')));
    await tester.pumpAndSettle();
    final toggle = tester.getRect(find.byKey(const Key('toggleMode')));
    await tester.tapAt(toggle.topCenter + const Offset(0, 2));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
    expect(find.byKey(const Key('forgotPassword')), findsNothing);
  });

  testWidgets('a screen reader hears each text link as a button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byKey(const Key('forgotPassword'))),
      isSemantics(
        label: 'Forgot password?',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('toggleMode'))),
      isSemantics(
        label: 'New here? Create account',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a screen reader reaches the eye as its own button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    final eye = find.byKey(const Key('togglePassword'));
    final eyeNode = tester.getSemantics(eye);
    expect(
      eyeNode.id,
      isNot(tester.getSemantics(find.byKey(const Key('password'))).id),
      reason: 'merged into the field, the eye cannot be reached or used',
    );
    expect(
      eyeNode,
      isSemantics(isButton: true, hasTapAction: true, tooltip: 'Show password'),
    );

    // The tap a screen reader sends, not a pointer tap on the widget.
    eyeNode.owner!.performAction(eyeNode.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(_field(tester, 'password').obscureText, isFalse);
    expect(tester.getSemantics(eye).tooltip, 'Hide password');
    semantics.dispose();
  });

  testWidgets('the password rule shows on sign up only', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    expect(find.text('At least 8 characters'), findsNothing);

    await _toRegister(tester);
    expect(find.text('At least 8 characters'), findsOneWidget);

    await _toRegister(tester);
    expect(find.text('At least 8 characters'), findsNothing);
  });

  testWidgets('a validation message sits under the field it is about', (
    tester,
  ) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();
    await _toRegister(tester);

    // Email and password filled, name left empty: the name is the problem.
    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    final message = find.text('Enter your name.');
    expect(message, findsOneWidget);
    final name = tester.getRect(find.byKey(const Key('fullName')));
    final email = tester.getRect(find.byKey(const Key('email')));
    final top = tester.getRect(message).top;
    expect(top, greaterThanOrEqualTo(name.bottom));
    expect(top, lessThan(email.top));

    // An empty password: the message belongs under the password field.
    await tester.enterText(find.byKey(const Key('fullName')), 'Juan');
    await tester.enterText(find.byKey(const Key('password')), '');
    await _tapKey(tester, 'submit');
    await tester.pumpAndSettle();

    final pwMessage = find.text('Enter your password.');
    expect(pwMessage, findsOneWidget);
    expect(find.text('Enter your name.'), findsNothing);
    final password = tester.getRect(find.byKey(const Key('password')));
    final submit = tester.getRect(find.byKey(const Key('submit')));
    expect(
      tester.getRect(pwMessage).top,
      greaterThanOrEqualTo(password.bottom),
    );
    expect(tester.getRect(pwMessage).bottom, lessThan(submit.top));
  });

  testWidgets(
    'a short password is flagged on sign up before anything is sent',
    (tester) async {
      // The server refuses fewer than 8 characters; saying so under the field
      // beats a round trip and a message about the whole form.
      final repo = FakeAuthRepository(onRegister: () async {});
      await _pump(tester, repo);
      await tester.pumpAndSettle();
      await _toRegister(tester);

      await tester.enterText(
        find.byKey(const Key('fullName')),
        'Juan Dela Cruz',
      );
      await _fillAndSubmit(tester, password: 'short12');
      await tester.pumpAndSettle();

      final message = find.text('Use at least 8 characters.');
      expect(message, findsOneWidget);
      expect(repo.registerCalls, 0, reason: 'checked before anything is sent');
      final password = tester.getRect(find.byKey(const Key('password')));
      final submit = tester.getRect(find.byKey(const Key('submit')));
      expect(
        tester.getRect(message).top,
        greaterThanOrEqualTo(password.bottom),
      );
      expect(tester.getRect(message).bottom, lessThan(submit.top));

      // Eight is enough.
      await tester.enterText(find.byKey(const Key('password')), 'short123');
      await tester.pump();
      expect(message, findsNothing, reason: 'editing the field clears it');
      await _tapKey(tester, 'submit');
      await tester.pumpAndSettle();
      expect(repo.registerCalls, 1);
    },
  );

  testWidgets('signing in never applies the sign-up length rule', (
    tester,
  ) async {
    // An account made before the rule must still be able to sign in.
    final repo = FakeAuthRepository(onLogin: () async => _user());
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester, password: 'short');
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters.'), findsNothing);
    expect(repo.loginCalls, 1);
  });

  testWidgets('a bad email is flagged under the email field', (tester) async {
    await _pump(tester, FakeAuthRepository());
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester, email: 'juan');
    await tester.pumpAndSettle();

    final message = find.text('That does not look like an email.');
    expect(message, findsOneWidget);
    final email = tester.getRect(find.byKey(const Key('email')));
    final password = tester.getRect(find.byKey(const Key('password')));
    expect(tester.getRect(message).top, greaterThanOrEqualTo(email.bottom));
    expect(tester.getRect(message).bottom, lessThan(password.top));
  });

  testWidgets('fits 320 dp at 2.0x text in both modes without overflow', (
    tester,
  ) async {
    await _pumpSmallLargeText(tester, FakeAuthRepository());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Sign up with every message showing is the tallest, widest the form gets.
    await tester.ensureVisible(find.byKey(const Key('toggleMode')));
    await tester.pumpAndSettle();
    await _toRegister(tester);
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'submit');
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
