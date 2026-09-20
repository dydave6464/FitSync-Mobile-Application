/// One weigh-in.
class BodyWeightPoint {
  const BodyWeightPoint({required this.loggedOn, required this.weightKg});

  /// `YYYY-MM-DD`, kept as a string for the same reason [SessionHistoryEntry]
  /// does: it is only compared and displayed, and parsing invites a timezone
  /// shift that moves an entry to the wrong day.
  final String loggedOn;
  final double weightKg;

  factory BodyWeightPoint.fromJson(Map<String, dynamic> json) =>
      BodyWeightPoint(
        loggedOn: json['loggedOn'] as String,
        weightKg: (json['weightKg'] as num).toDouble(),
      );
}

/// The dashed line behind the series: the user's goal, or where they started.
class BodyWeightReference {
  const BodyWeightReference({required this.kind, required this.weightKg});

  /// `'goal'` or `'start'`.
  final String kind;
  final double weightKg;

  String get label => kind == 'goal' ? 'goal' : 'start';

  factory BodyWeightReference.fromJson(Map<String, dynamic> json) =>
      BodyWeightReference(
        kind: json['kind'] as String,
        weightKg: (json['weightKg'] as num).toDouble(),
      );
}

class BodyWeightSeries {
  const BodyWeightSeries({
    required this.widened,
    required this.points,
    required this.reference,
    required this.unit,
  });

  /// True when the chosen period held fewer than two entries and the server
  /// reached further back rather than return an undrawable card.
  final bool widened;

  final List<BodyWeightPoint> points;
  final BodyWeightReference? reference;

  /// `'kg'` or `'lb'` — display only. Everything above is kilograms.
  final String unit;

  factory BodyWeightSeries.fromJson(Map<String, dynamic> json) =>
      BodyWeightSeries(
        widened: json['widened'] as bool? ?? false,
        points: [
          for (final p in (json['points'] as List<dynamic>? ?? const []))
            BodyWeightPoint.fromJson(p as Map<String, dynamic>),
        ],
        reference: json['reference'] == null
            ? null
            : BodyWeightReference.fromJson(
                json['reference'] as Map<String, dynamic>,
              ),
        unit: json['unit'] as String? ?? 'kg',
      );
}
