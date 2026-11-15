import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/units.dart';
import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy, exerciseDetailProvider;
import '../../nutrition/presentation/providers.dart'
    show mealSuggestionsProvider, nutritionDayProvider;
import '../../plans/presentation/providers.dart' show activePlanProvider;
import '../../sessions/presentation/providers.dart'
    show activeSessionProvider, trainingAnalyticsProvider;
import '../data/profile_repository.dart';
import '../domain/body_weight.dart';
import '../domain/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);

/// The signed-in user's profile.
///
/// An [AsyncNotifier] rather than a [FutureProvider] because every write
/// returns the updated profile, so the screens can keep this current without
/// a second round trip.
class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() => ref.watch(profileRepositoryProvider).load();

  /// The profile fields the body-weight card is drawn from on the server.
  ///
  /// `goalWeightKg` is the dashed reference line readReference() reads
  /// straight out of `users`, and a changed `weightKg` makes the profile
  /// write a `body_weight_logs` row of its own. Either one leaves the cached
  /// series wrong; patching anything else changes nothing the card shows.
  static const _bodyWeightFields = {'weightKg', 'goalWeightKg'};

  /// The profile fields the server works today's calorie and protein target
  /// out from (server/src/lib/nutrition-target.js; `mainGoal` comes through
  /// [setGoals]). The Nutrition day carries that target and the meal
  /// suggestions are fitted to it, so a change to any of these leaves both
  /// wrong -- the ring, "Fits the ~... left", and "Add your weight and
  /// height..." once the last missing figure is filled in.
  static const _targetFields = {
    'weightKg',
    'heightCm',
    'dateOfBirth',
    'sex',
    'activityLevel',
  };

  // Each write replaces state only on success. A failed write leaves the
  // profile already on screen intact and rethrows, so the caller can show the
  // error without the form underneath it disappearing.
  Future<void> patch(Map<String, dynamic> fields) async {
    state = AsyncData(await ref.read(profileRepositoryProvider).patch(fields));
    // Setting this state is not enough on its own: bodyWeightProvider holds
    // what the server computed from these same fields, and nothing else
    // refetches it -- the mirror of the invalidation showLogBodyWeightSheet
    // already does in the other direction.
    if (fields.keys.any(_bodyWeightFields.contains)) {
      // The whole family rather than one period. A goal is not per-period, so
      // every segment the user has already opened is holding the old line.
      ref.invalidate(bodyWeightProvider);
    }
    if (fields.keys.any(_targetFields.contains)) _refreshDailyTarget();
    // Suggested plates carry the usual rice and skip the avoided foods; the
    // day's target does not move.
    if (fields.containsKey('usualRiceCups') ||
        fields.containsKey('avoidFoods')) {
      ref.invalidate(mealSuggestionsProvider);
    }
  }

  /// Refetches the day on screen and every meal's suggestions (the whole
  /// family: the meal shown changes with the clock).
  void _refreshDailyTarget() {
    ref.invalidate(nutritionDayProvider);
    ref.invalidate(mealSuggestionsProvider);
  }

  Future<void> setEquipment(List<int> equipmentIds) async {
    state = AsyncData(
      await ref.read(profileRepositoryProvider).setEquipment(equipmentIds),
    );
  }

  Future<void> setInjuries(List<SelectedInjury> injuries) async {
    state = AsyncData(
      await ref.read(profileRepositoryProvider).setInjuries(injuries),
    );
    // Both hold exercises tagged with `coaching` from the OLD injury list --
    // only a fresh fetch reads the gate again under the new one. The same
    // goes for every exercise detail opened so far: its `contraindicated`
    // flag, behind the "loads an injury you reported" warning, was worked out
    // from the old list too (the whole family).
    ref.invalidate(activePlanProvider);
    ref.invalidate(activeSessionProvider);
    ref.invalidate(exerciseDetailProvider);
  }

  Future<void> setTrainingDays(List<int> weekdays) async {
    state = AsyncData(
      await ref.read(profileRepositoryProvider).setTrainingDays(weekdays),
    );
    // The server counts the chosen days for the plan's days a week and for
    // Progress's adherence target (PT-18), so both read the new count. The
    // whole analytics family: every period opened holds the old target.
    ref.invalidate(activePlanProvider);
    ref.invalidate(trainingAnalyticsProvider);
  }

  Future<void> setGoals(List<String> goals, String mainGoal) async {
    state = AsyncData(
      await ref.read(profileRepositoryProvider).setGoals(goals, mainGoal),
    );
    // The main goal moves the target: -500 to lose, +250 to gain.
    _refreshDailyTarget();
  }

  Future<CompletedOnboarding> completeOnboarding() async {
    final result = await ref
        .read(profileRepositoryProvider)
        .completeOnboarding();
    state = AsyncData(result.profile);
    return result;
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
  retry: apiRetryPolicy,
);

// Lookup data: fetched once and shared by the onboarding steps and their
// Settings editors.
final equipmentOptionsProvider = FutureProvider<List<EquipmentOption>>(
  (ref) => ref.watch(profileRepositoryProvider).equipmentOptions(),
  retry: apiRetryPolicy,
);

final injuryOptionsProvider = FutureProvider<List<InjuryOption>>(
  (ref) => ref.watch(profileRepositoryProvider).injuryOptions(),
  retry: apiRetryPolicy,
);

/// The clock the weigh-in sheet reads "today" from; a test fixes it.
final bodyWeightClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The unit every weight in the app is rendered in and typed in.
///
/// Kilograms until the profile arrives, and if it fails: that is the column's
/// own NOT NULL default, and it beats holding every weight on screen behind a
/// request that has nothing to do with them.
final weightUnitProvider = Provider<WeightUnit>(
  (ref) => ref.watch(profileProvider).value?.weightUnit ?? WeightUnit.kg,
);

/// Keyed on period so switching the segment refetches only this card.
final bodyWeightProvider = FutureProvider.family<BodyWeightSeries, String>(
  (ref, period) => ref.watch(profileRepositoryProvider).bodyWeight(period),
);
