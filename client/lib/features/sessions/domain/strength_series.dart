class StrengthPoint {
  const StrengthPoint({required this.label, required this.e1rmKg});
  final String label;
  final double e1rmKg;

  factory StrengthPoint.fromJson(Map<String, dynamic> json) => StrengthPoint(
        label: json['label'] as String,
        e1rmKg: (json['e1rmKg'] as num).toDouble(),
      );
}

class StrengthOption {
  const StrengthOption({required this.exerciseId, required this.name, required this.sets});
  final int exerciseId;
  final String name;
  final int sets;

  factory StrengthOption.fromJson(Map<String, dynamic> json) => StrengthOption(
        exerciseId: json['exerciseId'] as int,
        name: json['name'] as String,
        sets: json['sets'] as int,
      );
}

class StrengthSeries {
  const StrengthSeries({
    required this.exerciseId,
    required this.xAxis,
    required this.points,
    required this.options,
  });

  final int? exerciseId;

  /// `'set'` when this is a single session plotted set by set — the shape a
  /// first workout takes so the card draws a line rather than a dot — and
  /// `'date'` once there is history. Decided by the server, never inferred
  /// from the point count.
  final String xAxis;

  final List<StrengthPoint> points;
  final List<StrengthOption> options;

  bool get isSingleSession => xAxis == 'set';

  factory StrengthSeries.fromJson(Map<String, dynamic> json) => StrengthSeries(
        exerciseId: json['exerciseId'] as int?,
        xAxis: json['xAxis'] as String? ?? 'date',
        points: [
          for (final p in (json['points'] as List<dynamic>? ?? const []))
            StrengthPoint.fromJson(p as Map<String, dynamic>),
        ],
        options: [
          for (final o in (json['options'] as List<dynamic>? ?? const []))
            StrengthOption.fromJson(o as Map<String, dynamic>),
        ],
      );
}
