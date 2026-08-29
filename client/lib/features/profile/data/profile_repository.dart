import '../../../core/api_client.dart';
import '../domain/profile.dart';

/// What `POST /profile/complete-onboarding` returns: the finished profile and
/// the plan that was generated for it.
///
/// The plan is carried as raw JSON here so this layer does not depend on the
/// plans feature; the plan screen parses it into its own model.
typedef CompletedOnboarding = ({Profile profile, Map<String, dynamic>? plan});

class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<Profile> load() async =>
      Profile.fromJson((await _api.getJson('/api/v1/profile'))['profile']
          as Map<String, dynamic>);

  /// Sends exactly the keys it is given. The server treats an absent key as
  /// "leave alone" and an explicit null as "clear", so passing a full object
  /// with nulls would wipe fields the user never touched.
  Future<Profile> patch(Map<String, dynamic> fields) async =>
      Profile.fromJson((await _api.patchJson('/api/v1/profile', fields))['profile']
          as Map<String, dynamic>);

  /// The server replaces the whole set, so this sends every id the user has
  /// selected — not a delta.
  Future<Profile> setEquipment(List<int> equipmentIds) async => Profile.fromJson(
      (await _api.putJson('/api/v1/profile/equipment',
          {'equipmentIds': equipmentIds}))['profile'] as Map<String, dynamic>);

  Future<Profile> setInjuries(List<SelectedInjury> injuries) async =>
      Profile.fromJson((await _api.putJson('/api/v1/profile/injuries',
          {'injuries': injuries.map((i) => i.toJson()).toList()}))['profile']
          as Map<String, dynamic>);

  Future<CompletedOnboarding> completeOnboarding() async {
    final data =
        await _api.postJson('/api/v1/profile/complete-onboarding', const {});
    return (
      profile: Profile.fromJson(data['profile'] as Map<String, dynamic>),
      plan: data['plan'] as Map<String, dynamic>?,
    );
  }

  Future<List<EquipmentOption>> equipmentOptions() async =>
      ((await _api.getJson('/api/v1/equipment'))['equipment'] as List<dynamic>)
          .map((e) => EquipmentOption.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  Future<List<InjuryOption>> injuryOptions() async =>
      ((await _api.getJson('/api/v1/injuries'))['injuries'] as List<dynamic>)
          .map((e) => InjuryOption.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
}
