import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/app_shell.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/auth/presentation/sign_in_screen.dart';

AuthUser _user({bool onboardingCompleted = false}) => AuthUser(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: onboardingCompleted,
      isPremium: false,
    );

/// Drives the shell's four branches directly. [onBuild] receives how many
/// times `build()` has already run, so a test can fail the first attempt and
/// succeed on the retry.
class FakeAuthController extends AuthController {
  FakeAuthController(this.onBuild);

  final Future<AuthState> Function(int callCount) onBuild;
  int _calls = 0;

  @override
  Future<AuthState> build() => onBuild(_calls++);
}

Future<void> _pumpShell(
  WidgetTester tester,
  Future<AuthState> Function(int callCount) onBuild,
) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => FakeAuthController(onBuild)),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );

void main() {
  testWidgets('shows a spinner while auth state is resolving', (tester) async {
    final pending = Completer<AuthState>();
    await _pumpShell(tester, (_) => pending.future);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(AuthState.signedOut);
    await tester.pumpAndSettle();
  });

  testWidgets('signed out shows the sign-in screen', (tester) async {
    await _pumpShell(tester, (_) async => AuthState.signedOut);
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('an unfinished profile shows the onboarding flow', (tester) async {
    await _pumpShell(
      tester,
      (_) async => AuthState(AuthStatus.onboarding, _user()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingPlaceholder), findsOneWidget);
  });

  testWidgets('a finished profile shows the plan screen', (tester) async {
    await _pumpShell(
      tester,
      (_) async => AuthState(
        AuthStatus.ready,
        _user(onboardingCompleted: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlanPlaceholder), findsOneWidget);
  });

  testWidgets('an error shows the message and recovers on retry', (tester) async {
    await _pumpShell(tester, (callCount) async {
      if (callCount == 0) {
        throw const ApiException('SERVER_ERROR', 'The server is having a moment.');
      }
      return AuthState.signedOut;
    });
    await tester.pumpAndSettle();

    expect(find.text('The server is having a moment.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget,
        reason: 'retry must re-read the controller, not just clear the error');
  });
}
