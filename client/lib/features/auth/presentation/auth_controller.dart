import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/token_store.dart';
import '../../exercises/presentation/providers.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

/// Where the app can be, as far as authentication is concerned.
///
/// `onboarding` is a signed-in state: the user has a valid token but has not
/// finished the four onboarding steps, so the shell must not show them the
/// plan yet.
enum AuthStatus { signedOut, onboarding, ready }

class AuthState {
  const AuthState(this.status, [this.user]);

  final AuthStatus status;
  final AuthUser? user;

  static const signedOut = AuthState(AuthStatus.signedOut);
}

/// The JWT store the auth layer reads and writes.
///
/// Note that [apiClientProvider] builds its own [TokenStore]. Both default to
/// [PluginSecureStore] over the same platform keystore and the same key, so
/// in production they observe identical state. They are separate instances
/// only because `apiClientProvider` predates this provider and moving it here
/// would make the exercises providers import the auth feature. Override both
/// together in any test that needs them to agree.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  ),
);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final tokens = ref.watch(tokenStoreProvider);
    final token = await tokens.read();
    if (token == null || token.isEmpty) return AuthState.signedOut;

    try {
      return _forUser(await ref.watch(authRepositoryProvider).me());
    } on ApiException catch (error) {
      // An expired or revoked token would otherwise strand the user on a
      // screen that can never load. Drop it and show sign-in instead.
      if (error.code == 'UNAUTHENTICATED') {
        await tokens.clear();
        return AuthState.signedOut;
      }
      // Anything else is a real failure the shell should surface with a
      // retry, so let it become an AsyncError.
      rethrow;
    }
  }

  AuthState _forUser(AuthUser user) => AuthState(
        user.onboardingCompleted ? AuthStatus.ready : AuthStatus.onboarding,
        user,
      );

  /// Called by the sign-in screen once a token is already stored, so the
  /// shell moves on without a second round trip to `/auth/me`.
  void onAuthenticated(AuthUser user) => state = AsyncData(_forUser(user));

  /// Called when onboarding finishes. Without it the shell would keep showing
  /// the wizard until something else re-read `/auth/me`.
  void onOnboardingCompleted() {
    final user = state.value?.user;
    if (user == null) return;
    state = AsyncData(AuthState(AuthStatus.ready, user));
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(AuthState.signedOut);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
  retry: apiRetryPolicy,
);
