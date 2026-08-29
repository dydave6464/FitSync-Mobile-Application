/// A piece of equipment the user can own, as the server names it.
class EquipmentOption {
  const EquipmentOption({required this.equipmentId, required this.name});

  final int equipmentId;
  final String name;

  factory EquipmentOption.fromJson(Map<String, dynamic> json) => EquipmentOption(
        equipmentId: json['equipmentId'] as int,
        name: json['name'] as String,
      );
}

/// An injury region offered by the server.
///
/// [isLateral] is why the client does not need its own list of which regions
/// have sides — the server says so, and the server is what rejects a side on
/// a region that does not have one.
class InjuryOption {
  const InjuryOption({
    required this.injuryId,
    required this.name,
    required this.isLateral,
    required this.regionGroup,
  });

  final int injuryId;
  final String name;
  final bool isLateral;
  final String regionGroup;

  factory InjuryOption.fromJson(Map<String, dynamic> json) => InjuryOption(
        injuryId: json['injuryId'] as int,
        name: json['name'] as String,
        isLateral: json['isLateral'] as bool? ?? false,
        regionGroup: json['regionGroup'] as String? ?? '',
      );
}

/// An injury the user has selected. [side] is null for a non-lateral region,
/// and the server rejects a non-null side on one.
class SelectedInjury {
  const SelectedInjury({required this.injuryId, this.side});

  final int injuryId;
  final String? side;

  factory SelectedInjury.fromJson(Map<String, dynamic> json) => SelectedInjury(
        injuryId: json['injuryId'] as int,
        side: json['side'] as String?,
      );

  /// Omits `side` entirely when there is none, rather than sending null —
  /// the wire shape the server documents for a non-lateral injury.
  Map<String, dynamic> toJson() => {
        'injuryId': injuryId,
        if (side != null) 'side': side,
      };

  SelectedInjury withSide(String? value) =>
      SelectedInjury(injuryId: injuryId, side: value);
}

class Profile {
  const Profile({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.onboardingCompleted,
    required this.isPremium,
    required this.notificationsEnabled,
    required this.equipment,
    required this.injuries,
    this.sex,
    this.dateOfBirth,
    this.heightCm,
    this.weightKg,
    this.goalWeightKg,
    this.mainGoal,
    this.fitnessLevel,
    this.activityLevel,
    this.trainingLocation,
    this.city,
  });

  final int userId;
  final String email;
  final String fullName;
  final bool onboardingCompleted;
  final bool isPremium;
  final bool notificationsEnabled;
  final List<EquipmentOption> equipment;
  final List<SelectedInjury> injuries;

  final String? sex;

  /// Kept as the wire's `YYYY-MM-DD` string rather than a `DateTime`.
  /// A date of birth has no time and no zone; parsing it into a local
  /// `DateTime` and formatting it back is how a birthday drifts by a day.
  final String? dateOfBirth;

  final double? heightCm;
  final double? weightKg;
  final double? goalWeightKg;
  final String? mainGoal;
  final String? fitnessLevel;
  final String? activityLevel;
  final String? trainingLocation;
  final String? city;

  /// MySQL `DECIMAL` columns arrive as a JSON number through some driver
  /// configurations and as a string through others. Going via `toString()`
  /// handles both and stops a `type 'String' is not a subtype of type
  /// 'double'` crash at runtime.
  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return num.tryParse(value.toString())?.toDouble();
  }

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        userId: json['userId'] as int,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
        isPremium: json['isPremium'] as bool? ?? false,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        equipment: ((json['equipment'] as List<dynamic>?) ?? const [])
            .map((e) => EquipmentOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        injuries: ((json['injuries'] as List<dynamic>?) ?? const [])
            .map((e) => SelectedInjury.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        sex: json['sex'] as String?,
        dateOfBirth: json['dateOfBirth'] as String?,
        heightCm: _toDouble(json['heightCm']),
        weightKg: _toDouble(json['weightKg']),
        goalWeightKg: _toDouble(json['goalWeightKg']),
        mainGoal: json['mainGoal'] as String?,
        fitnessLevel: json['fitnessLevel'] as String?,
        activityLevel: json['activityLevel'] as String?,
        trainingLocation: json['trainingLocation'] as String?,
        city: json['city'] as String?,
      );
}
