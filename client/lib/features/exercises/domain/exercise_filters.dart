import 'muscle_regions.dart';

class FilterOption {
  /// [label] falls back to [value] because only equipment carries one: the
  /// catalogue tags gear in its own vocabulary ('smith machine', 'ez
  /// barbell') and the server rolls those up to the names onboarding uses,
  /// while a muscle group is already the word the user would say.
  const FilterOption({required this.value, required this.count, String? label})
    : label = label ?? value;

  /// What the API is sent. Stable, and not what the user reads.
  final String value;

  /// What the user reads.
  final String label;

  final int count;

  factory FilterOption.fromJson(Map<String, dynamic> json) => FilterOption(
    value: json['value'] as String,
    // Absent on muscle groups, and on any server predating the rollup.
    label: json['label'] as String?,
    count: (json['count'] as num).toInt(),
  );
}

class ExerciseFilters {
  const ExerciseFilters({required this.muscleGroups, required this.equipment});

  final List<FilterOption> muscleGroups;
  final List<FilterOption> equipment;

  static List<FilterOption> _parse(Object? raw) =>
      (raw as List<dynamic>? ?? const [])
          .map((e) => FilterOption.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

  factory ExerciseFilters.fromJson(Map<String, dynamic> json) =>
      ExerciseFilters(
        muscleGroups: _parse(json['muscleGroups']),
        equipment: _parse(json['equipment']),
      );
}

/// The filter selection currently applied. Null means "no filter".
class SelectedFilters {
  const SelectedFilters({this.region, this.equipment, this.search});

  /// The body area the library's muscle buttons have narrowed to, or null for
  /// "All".
  ///
  /// An area rather than one raw muscle group: the catalogue has nineteen
  /// groups and a person looking for back work means lats, traps and upper
  /// back alike. [MuscleRegion.muscleGroups] is what is actually sent.
  final MuscleRegion? region;

  final String? equipment;

  /// A name fragment, matched server-side against the whole catalogue rather
  /// than against the pages already fetched -- the list arrives 20 rows at a
  /// time, so filtering locally would only ever search what happens to have
  /// been scrolled past.
  final String? search;

  SelectedFilters withRegion(MuscleRegion? value) =>
      SelectedFilters(region: value, equipment: equipment, search: search);

  SelectedFilters withEquipment(String? value) =>
      SelectedFilters(region: region, equipment: value, search: search);

  SelectedFilters withSearch(String? value) =>
      SelectedFilters(region: region, equipment: equipment, search: value);

  bool get isEmpty => region == null && equipment == null && search == null;

  /// Whether any CHIP is lit. Separate from [isEmpty] because the chip
  /// strip's "Clear" answers for the chips only: the search box carries its
  /// own clear button, and wiping text the user can still see from a control
  /// that does not look attached to it is the more surprising behaviour.
  bool get hasChipFilter => region != null || equipment != null;

  @override
  bool operator ==(Object other) =>
      other is SelectedFilters &&
      other.region == region &&
      other.equipment == equipment &&
      other.search == search;

  @override
  int get hashCode => Object.hash(region, equipment, search);
}
