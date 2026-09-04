import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

/// Signing out must not leave one account's data readable by the next.
///
/// profileProvider is an AsyncNotifierProvider and activePlanProvider a
/// FutureProvider; neither is autoDispose, so both cache for the lifetime of
/// the app. Clearing the token alone leaves that cache intact, and the next
/// user to sign in is handed the previous user's profile.

Profile _profile({required int userId, required String email}) => Profile(
      userId: userId,
      email: email,
      fullName: 'User $userId',
      onboardingCompleted: true,
      isPremium: false,
      notificationsEnabled: true,
      equipment: const [],
      injuries: const [],
      heightCm: userId * 10.0,
    );

/// Hands out a different profile on each call, so a cached value is
/// distinguishable from a freshly loaded one.
class SequenceProfileRepository implements ProfileRepository {
  SequenceProfileRepository(this._profiles);

  final List<Profile> _profiles;
  int loads = 0;

  @override
  Future<Profile> load() async {
    final p = _profiles[loads.clamp(0, _profiles.length - 1)];
    loads += 1;
    return p;
  }

  @override
  Future<Profile> patch(Map<String, dynamic> fields) => throw UnimplementedError();
  @override
  Future<Profile> setEquipment(List<int> equipmentIds) => throw UnimplementedError();
  @override
  Future<Profile> setInjuries(List<SelectedInjury> injuries) =>
      throw UnimplementedError();
  @override
  Future<CompletedOnboarding> completeOnboarding() => throw UnimplementedError();
  @override
  Future<List<EquipmentOption>> equipmentOptions() async => const [];
  @override
  Future<List<InjuryOption>> injuryOptions() async => const [];
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.tokens);
  final TokenStore tokens;

  @override
  Future<AuthUser> me() => throw UnimplementedError();
  @override
  Future<void> signOut() => tokens.clear();
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
  Future<AuthUser> signInWithGoogle(String idToken) => throw UnimplementedError();
  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
  @override
  Future<void> resendVerification({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();
}

void main() {
  test('signing out drops the previous account\'s profile', () async {
    final first = _profile(userId: 1, email: 'juan@example.com');
    final second = _profile(userId: 2, email: 'maria@example.com');
    final profiles = SequenceProfileRepository([first, second]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');

    final container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
      profileRepositoryProvider.overrideWithValue(profiles),
    ]);
    addTearDown(container.dispose);

    // Juan is signed in and his profile is loaded and cached.
    expect((await container.read(profileProvider.future)).email,
        'juan@example.com');
    expect(profiles.loads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    // Maria signs in on the same device. She must not be shown Juan's profile.
    final afterSignOut = await container.read(profileProvider.future);
    expect(afterSignOut.email, 'maria@example.com',
        reason: 'the next account got the previous account\'s cached profile');
    expect(profiles.loads, 2, reason: 'the profile was not re-fetched');
  });

  test('signing out clears the stored token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
      profileRepositoryProvider
          .overrideWithValue(SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')])),
    ]);
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).signOut();
    expect(await tokens.read(), isNull);
  });
}
