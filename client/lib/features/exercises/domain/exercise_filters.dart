class FilterOption {
  const FilterOption({required this.value, required this.count});

  final String value;
  final int count;

  factory FilterOption.fromJson(Map<String, dynamic> json) => FilterOption(
        value: json['value'] as String,
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

  factory ExerciseFilters.fromJson(Map<String, dynamic> json) => ExerciseFilters(
        muscleGroups: _parse(json['muscleGroups']),
        equipment: _parse(json['equipment']),
      );
}

/// The filter selection currently applied. Null means "no filter".
class SelectedFilters {
  const SelectedFilters({this.muscleGroup, this.equipment, this.search});

  final String? muscleGroup;
  final String? equipment;

  /// A name fragment, matched server-side against the whole catalogue rather
  /// than against the pages already fetched -- the list arrives 20 rows at a
  /// time, so filtering locally would only ever search what happens to have
  /// been scrolled past.
  final String? search;

  SelectedFilters withMuscleGroup(String? value) =>
      SelectedFilters(muscleGroup: value, equipment: equipment, search: search);

  SelectedFilters withEquipment(String? value) =>
      SelectedFilters(muscleGroup: muscleGroup, equipment: value, search: search);

  SelectedFilters withSearch(String? value) => SelectedFilters(
        muscleGroup: muscleGroup,
        equipment: equipment,
        search: value,
      );

  bool get isEmpty => muscleGroup == null && equipment == null && search == null;

  /// Whether any CHIP is lit. Separate from [isEmpty] because the chip
  /// strip's "Clear" answers for the chips only: the search box carries its
  /// own clear button, and wiping text the user can still see from a control
  /// that does not look attached to it is the more surprising behaviour.
  bool get hasChipFilter => muscleGroup != null || equipment != null;

  @override
  bool operator ==(Object other) =>
      other is SelectedFilters &&
      other.muscleGroup == muscleGroup &&
      other.equipment == equipment &&
      other.search == search;

  @override
  int get hashCode => Object.hash(muscleGroup, equipment, search);
}
