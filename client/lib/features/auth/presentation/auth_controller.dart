import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/token_store.dart';
import '../../activity/presentation/providers.dart'
    show activityProvider, stepAccessProvider;
import '../../admin/domain/admin_user.dart';
import '../../ads/presentation/ad_slot.dart'
    show adViewsReportedProvider, currentAdProvider;
import '../../admin/presentation/providers.dart' show adminRepositoryProvider;
import '../../exercises/presentation/providers.dart';
import '../../home/presentation/plan_ready.dart';
import '../../nutrition/presentation/providers.dart'
    show mealSuggestionsProvider, nutritionDayProvider, nutritionDateProvider, recentFoodsProvider;
import '../../plans/presentation/providers.dart';
import '../../pro/presentation/providers.dart' show proPendingCheckoutProvider;
import '../../recovery/presentation/providers.dart';
import '../../reminders/data/reminder_scheduler.dart';
import '../../reminders/presentation/providers.dart';
import '../../routine/presentation/providers.dart';
import '../../sessions/presentation/providers.dart';
import '../../sessions/presentation/workout_draft.dart';
import '../../profile/presentation/providers.dart';
import '../../streaks/presentation/providers.dart';
import '../data/auth_repository.dart';
import '../data/google_sign_in_gateway.dart';
import '../domain/auth_user.dart';
import '../domain/sign_in_outcome.dart';

/// Where the app can be, as far as authentication is concerned.
///
/// `onboarding` is a signed-in state: the user has a valid token but has not
/// finished the four onboarding steps, so the shell must not show them the
/// plan yet.
///
/// `admin` is an admin signed in with an admin token: the shell shows the
/// admin tabs, and [AuthState.admin] is set instead of [AuthState.user].
enum AuthStatus { signedOut, onboarding, ready, admin }

/// Why a session ended, when the sign-in screen has something to say about
/// it. A plain sign-out needs no words: the user asked for it.
enum SignOutReason { accountDeleted, suspended }

class AuthState {
  const AuthState(this.status, [this.user, this.reason, this.admin]);

  final AuthStatus status;
  final AuthUser? user;

  /// Set only on a signed-out state, and only when the screen should say why.
  final SignOutReason? reason;

  /// Set only on an [AuthStatus.admin] state.
  final AdminUser? admin;

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

final googleSignInGatewayProvider = Provider<GoogleSignInGateway>(
  (ref) => PluginGoogleSignInGateway(),
);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final tokens = ref.watch(tokenStoreProvider);
    final token = await tokens.read();
    if (token == null || token.isEmpty) return AuthState.signedOut;

    // An admin token is refused by /auth/me (and a trainee's by /admin/me),
    // so each is checked where it belongs. No role is a trainee: installs
    // from before roles stored none.
    if (await tokens.readRole() == 'admin') {
      try {
        final admin = await ref.watch(adminRepositoryProvider).me();
        return AuthState(AuthStatus.admin, null, null, admin);
      } on ApiException catch (error) {
        // An admin has no reminders to cancel.
        if (error.code == 'UNAUTHENTICATED') {
          await tokens.clear();
          return AuthState.signedOut;
        }
        rethrow;
      }
    }

    try {
      return _forUser(await ref.watch(authRepositoryProvider).me());
    } on ApiException catch (error) {
      // An expired or revoked token would otherwise strand the user on a
      // screen that can never load. Drop it and show sign-in instead.
      if (error.code == 'UNAUTHENTICATED') {
        await tokens.clear();
        await _cancelReminders();
        return AuthState.signedOut;
      }
      // Suspended by an admin: the token is no good until they are
      // reinstated, and the sign-in screen says why they are back there.
      if (error.code == 'ACCOUNT_SUSPENDED') {
        await tokens.clear();
        await _cancelReminders();
        return const AuthState(
          AuthStatus.signedOut,
          null,
          SignOutReason.suspended,
        );
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
  void onAuthenticated(AuthUser user) {
    // Belt and braces: clearing on the way in as well means a session that
    // begins without a clean sign-out cannot inherit the previous one either.
    _clearUserScopedCaches();
    state = AsyncData(_forUser(user));
  }

  /// After a password sign-in: a trainee goes to [onAuthenticated], an admin
  /// to [onAdminAuthenticated].
  void onSignedIn(SignInOutcome outcome) => switch (outcome) {
    TraineeSignedIn(:final user) => onAuthenticated(user),
    AdminSignedIn(:final admin) => onAdminAuthenticated(admin),
  };

  /// The admin's [onAuthenticated]: the token and the admin role are already
  /// stored, so the shell moves straight to the admin tabs.
  void onAdminAuthenticated(AdminUser admin) {
    // As onAuthenticated: nothing of a trainee who used this phone before
    // may stay in memory.
    _clearUserScopedCaches();
    state = AsyncData(AuthState(AuthStatus.admin, null, null, admin));
  }

  /// Called when onboarding finishes. Without it the shell would keep showing
  /// the wizard until something else re-read `/auth/me`.
  void onOnboardingCompleted() {
    final user = state.value?.user;
    if (user == null) return;
    state = AsyncData(AuthState(AuthStatus.ready, user));
  }

  /// Drop every cache that belongs to one signed-in user.
  ///
  /// None of these is autoDispose -- once built they live as long as the app
  /// does. Clearing the token alone therefore leaves the previous user's data
  /// sitting in memory, and the next account to sign in on the same device is
  /// handed it.
  ///
  /// `activeSessionProvider` is the one that leaks most visibly: an in-progress
  /// session carries its logged sets, so the next account opened the logger
  /// onto someone else's weights and reps already ticked into the table.
  ///
  /// `workoutDraftProvider` leaks the same way one step earlier: exercises
  /// ticked in the library and never started stayed ticked, so the next
  /// account opened "Log manually" to someone else's picks and a live Start
  /// button.
  ///
  /// Anything user-scoped added later belongs on this list. `autoDispose`
  /// providers do not -- `lastPerformanceProvider` and `alternativesProvider`
  /// are dropped when the screen holding them goes away, which sign-out does.
  ///
  /// `selectedFiltersProvider` is not user data in the way a logged set is,
  /// but it is still a trace of the previous account: the next one opened the
  /// library to a list narrowed by a word someone else typed.
  ///
  /// Lookup data (`equipmentOptionsProvider`, `injuryOptionsProvider`, the
  /// library's filter options) is the same for everyone and is deliberately
  /// kept. The exercises themselves are not: see the end of this list.
  ///
  /// `routineTodayProvider`, `homeSummaryProvider`, `trainingSummaryProvider`,
  /// `trainingAnalyticsProvider`, `sessionHistoryProvider`,
  /// `lastWorkoutProvider`, `pendingOutcomeProvider`, `recoveryOverviewProvider`,
  /// `streakProvider`, `reminderSettingsProvider`, `activityProvider` and
  /// `stepAccessProvider` belong on this list for the same reason: none of
  /// them is autoDispose, and each carries another account's training,
  /// recovery, routine, reminder or activity data across the sign-out.
  ///
  /// So does `proPendingCheckoutProvider`: the Pro screen re-checks the
  /// checkout it remembers, and the next account would ask the server about
  /// someone else's payment.
  ///
  /// `currentAdProvider` and `adViewsReportedProvider` are kept for the
  /// session: the ad on the cards, and the views already reported. The next
  /// account starts both afresh.
  ///
  /// `bodyWeightProvider` holds the weigh-ins Progress, the weigh-ins list and
  /// the coach report draw, and that list's delete is keyed by day: a leftover
  /// list would delete the next account's own weigh-in for the same date.
  /// `restSecondsProvider` is the rest length stored for this account.
  /// `exerciseDetailProvider` and `exerciseListProvider` are the parts of the
  /// catalogue that are not the same for everyone: the detail and each
  /// library row carry a `contraindicated` flag, behind the "loads an injury
  /// you reported" warning and badge, worked out for the signed-in user.
  /// Resetting `selectedFiltersProvider` does not rebuild the list when the
  /// filters were already at their default (the new value equals the old, so
  /// nothing is notified), so the list is cleared here itself, as a reload:
  /// a plain invalidate is a refresh that keeps the old rows as the data the
  /// library draws until the next account's first page arrives.
  /// `recentExercisesProvider` is autoDispose and needs no entry.
  void _clearUserScopedCaches() {
    ref.invalidate(profileProvider);
    ref.invalidate(activePlanProvider);
    ref.invalidate(activeSessionProvider);
    ref.invalidate(completedDaysProvider);
    ref.invalidate(workoutDraftProvider);
    ref.invalidate(selectedFiltersProvider);
    ref.invalidate(routineTodayProvider);
    ref.invalidate(homeSummaryProvider);
    ref.invalidate(trainingSummaryProvider);
    ref.invalidate(trainingAnalyticsProvider);
    ref.invalidate(sessionHistoryProvider);
    ref.invalidate(lastWorkoutProvider);
    ref.invalidate(pendingOutcomeProvider);
    ref.invalidate(recoveryOverviewProvider);
    ref.invalidate(streakProvider);
    ref.invalidate(reminderSettingsProvider);
    ref.invalidate(activityProvider);
    ref.invalidate(stepAccessProvider);
    ref.invalidate(nutritionDayProvider);
    ref.invalidate(nutritionDateProvider);
    ref.invalidate(recentFoodsProvider);
    ref.invalidate(mealSuggestionsProvider);
    ref.invalidate(planReadyProvider);
    ref.invalidate(proPendingCheckoutProvider);
    ref.invalidate(currentAdProvider);
    ref.invalidate(adViewsReportedProvider);
    ref.invalidate(bodyWeightProvider);
    ref.invalidate(restSecondsProvider);
    ref.invalidate(exerciseDetailProvider);
    ref.invalidate(exerciseListProvider, asReload: true);
  }

  Future<void> signOut() => _signOutLocally();

  /// Called once the server has deleted the account: the same clean-up as
  /// [signOut] (the token, this phone's reminders, every cached screen), then
  /// the sign-in screen says the account was deleted, so the user does not
  /// wonder why they are back there.
  Future<void> onAccountDeleted() =>
      _signOutLocally(SignOutReason.accountDeleted);

  Future<void> _signOutLocally([SignOutReason? reason]) async {
    final wasAdmin = state.value?.status == AuthStatus.admin;
    // Clears the role with the token.
    await ref.read(authRepositoryProvider).signOut();
    // The next account must not inherit this one's reminders. An admin has
    // none, so an admin's sign-out leaves the phone's reminders alone.
    if (!wasAdmin) await _cancelReminders();
    _clearUserScopedCaches();
    state = AsyncData(AuthState(AuthStatus.signedOut, null, reason));
  }

  /// Best-effort: a scheduler failure here must never strand the caller
  /// signed in (or, from [build]'s expired-token path, stuck on a screen
  /// that can never load) just because the phone's notification plugin had
  /// a bad moment.
  Future<void> _cancelReminders() async {
    try {
      await ref.read(reminderSchedulerProvider).cancelAll();
    } catch (error) {
      debugPrint('AuthController: cancelAll failed: $error');
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
  retry: apiRetryPolicy,
);
