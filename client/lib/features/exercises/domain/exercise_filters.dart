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
  const SelectedFilters({this.muscleGroup, this.equipment});

  final String? muscleGroup;
  final String? equipment;

  SelectedFilters withMuscleGroup(String? value) =>
      SelectedFilters(muscleGroup: value, equipment: equipment);

  SelectedFilters withEquipment(String? value) =>
      SelectedFilters(muscleGroup: muscleGroup, equipment: value);

  bool get isEmpty => muscleGroup == null && equipment == null;

  @override
  bool operator ==(Object other) =>
      other is SelectedFilters &&
      other.muscleGroup == muscleGroup &&
      other.equipment == equipment;

  @override
  int get hashCode => Object.hash(muscleGroup, equipment);
}
