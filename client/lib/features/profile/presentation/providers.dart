import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart' show apiClientProvider, apiRetryPolicy;
import '../data/profile_repository.dart';
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

  // Each write replaces state only on success. A failed write leaves the
  // profile already on screen intact and rethrows, so the caller can show the
  // error without the form underneath it disappearing.
  Future<void> patch(Map<String, dynamic> fields) async {
    state = AsyncData(await ref.read(profileRepositoryProvider).patch(fields));
  }

  Future<void> setEquipment(List<int> equipmentIds) async {
    state = AsyncData(
        await ref.read(profileRepositoryProvider).setEquipment(equipmentIds));
  }

  Future<void> setInjuries(List<SelectedInjury> injuries) async {
    state = AsyncData(
        await ref.read(profileRepositoryProvider).setInjuries(injuries));
  }

  Future<CompletedOnboarding> completeOnboarding() async {
    final result =
        await ref.read(profileRepositoryProvider).completeOnboarding();
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
