import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';

AuthUser _user({bool onboardingCompleted = false}) => AuthUser(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: onboardingCompleted,
      isPremium: false,
    );

/// An auth repository double. `me()` is supplied per test; `signOut()` clears
/// the same token store the controller reads, so the test can assert on it.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.tokens, {this.onMe});

  final TokenStore tokens;
  final Future<AuthUser> Function()? onMe;

  @override
  Future<AuthUser> me() => onMe!();

  @override
  Future<void> signOut() => tokens.clear();

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
  Future<AuthUser> signInWithGoogle(String idToken) =>
      throw UnimplementedError();
}

ProviderContainer _containerWith(TokenStore tokens, FakeAuthRepository repo) {
  final container = ProviderContainer(overrides: [
    tokenStoreProvider.overrideWithValue(tokens),
    authRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a launch with no stored token resolves to signedOut', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final container = _containerWith(tokens, FakeAuthRepository(tokens));

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.signedOut);
    expect(state.user, isNull);
  });

  test('a stored token for an unfinished profile resolves to onboarding', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final container = _containerWith(
      tokens,
      FakeAuthRepository(tokens,
          onMe: () async => _user(onboardingCompleted: false)),
    );

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.onboarding);
    expect(state.user!.email, 'juan@example.com');
  });

  test('a stored token for a finished profile resolves to ready', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final container = _containerWith(
      tokens,
      FakeAuthRepository(tokens,
          onMe: () async => _user(onboardingCompleted: true)),
    );

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.ready);
  });

  test('a rejected token resolves to signedOut and clears the token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('expired');
    final container = _containerWith(
      tokens,
      FakeAuthRepository(
        tokens,
        onMe: () async => throw const ApiException(
            'UNAUTHENTICATED', 'Sign in to continue.'),
      ),
    );

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.signedOut);
    expect(await tokens.read(), isNull,
        reason: 'an expired token must not strand the user on a screen that '
            'cannot load');
  });

  test('signOut moves a ready session to signedOut', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final container = _containerWith(
      tokens,
      FakeAuthRepository(tokens,
          onMe: () async => _user(onboardingCompleted: true)),
    );

    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).signOut();

    expect(container.read(authControllerProvider).value!.status,
        AuthStatus.signedOut);
    expect(await tokens.read(), isNull);
  });
}
