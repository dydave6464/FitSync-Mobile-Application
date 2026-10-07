/// One checklist condition: the wire value the server's SET column accepts,
/// the chip label, the notice's line about it, and its safety tip. The value
/// is a wire contract; the wording is copy the teacher has read.
typedef HealthCondition = ({
  String value,
  String label,
  String line,
  String tip,
});

const healthConditions = <HealthCondition>[
  (
    value: 'high_blood_pressure',
    label: 'High blood pressure',
    line:
        'Exercise is usually safe and helpful with high blood pressure, '
        'but your doctor should OK it first.',
    tip: "Breathe out as you lift; don't hold your breath.",
  ),
  (
    value: 'heart_condition',
    label: 'Heart condition',
    line:
        'Exercise is usually safe and helpful with a heart condition, '
        'but your doctor should OK it first.',
    tip:
        "Train only with your doctor's OK; stop if you get chest pain or "
        'unusual breathlessness.',
  ),
  (
    value: 'diabetes',
    label: 'Diabetes',
    line:
        'Exercise is usually safe and helpful with diabetes, '
        'but your doctor should OK it first.',
    tip:
        'Check your blood sugar before and after training; keep a '
        'fast-acting snack nearby.',
  ),
  (
    value: 'asthma',
    label: 'Asthma',
    line:
        'Exercise is usually safe and helpful with asthma, '
        'but your doctor should OK it first.',
    tip: 'Keep your inhaler nearby and warm up gradually.',
  ),
  (
    value: 'pregnancy',
    label: 'Pregnant or recently gave birth',
    line:
        'Exercise is usually safe and helpful during pregnancy and after '
        'giving birth, but your doctor should OK it first.',
    tip: "Follow your doctor's or midwife's advice; stop if anything feels wrong.",
  ),
  (
    value: 'recent_surgery',
    label: 'Surgery in the last 6 months',
    line:
        'Exercise is usually safe and helpful after surgery, '
        'but your doctor should OK it first.',
    tip: "Wait for your surgeon's clearance before training.",
  ),
  (
    value: 'other',
    label: 'Other condition',
    line:
        'Exercise is usually safe and helpful with your condition, '
        'but your doctor should OK it first.',
    tip: 'Ask your doctor which exercises are safe for you.',
  ),
];

/// The three warning-sign questions, each answered Yes or No.
const healthQuestions = <({String field, String label})>[
  (field: 'chestPain', label: 'Chest pain during physical activity?'),
  (field: 'dizziness', label: 'Dizziness or fainting?'),
  (
    field: 'supervisedOnly',
    label: 'A doctor tell you to exercise only with medical supervision?',
  ),
];

/// The health step's working answers.
///
/// [noneOfThese] is UI state: it is stored as an empty condition set. A null
/// question is unanswered, which is never valid. [optedOut] is "Don't save my
/// answers": nothing is stored, so the plan stays as it is.
class HealthAnswers {
  const HealthAnswers({
    this.conditions = const [],
    this.noneOfThese = false,
    this.chestPain,
    this.dizziness,
    this.supervisedOnly,
    this.acknowledged = false,
    this.consent = false,
    this.optedOut = false,
  });

  /// A stored check. A stored empty set is "None of these"; the boxes count
  /// as ticked when the server stamped them.
  factory HealthAnswers.fromJson(Map<String, dynamic> json) {
    final stored = (json['conditions'] as List<dynamic>).cast<String>();
    final conditions = [
      for (final c in healthConditions)
        if (stored.contains(c.value)) c.value,
    ];
    return HealthAnswers(
      conditions: conditions,
      noneOfThese: conditions.isEmpty,
      chestPain: json['chestPain'] as bool,
      dizziness: json['dizziness'] as bool,
      supervisedOnly: json['supervisedOnly'] as bool,
      acknowledged: json['acknowledgedAt'] != null,
      consent: json['consentedAt'] != null,
    );
  }

  final List<String> conditions;
  final bool noneOfThese;
  final bool? chestPain;
  final bool? dizziness;
  final bool? supervisedOnly;
  final bool acknowledged;
  final bool consent;
  final bool optedOut;

  bool get hasWarning =>
      chestPain == true || dizziness == true || supervisedOnly == true;

  bool get isPositive => conditions.isNotEmpty || hasWarning;

  bool get isComplete =>
      (noneOfThese || conditions.isNotEmpty) &&
      chestPain != null &&
      dizziness != null &&
      supervisedOnly != null;

  /// Whether Continue (or Save) may proceed.
  bool get isValid =>
      isComplete && (!isPositive || optedOut || (acknowledged && consent));

  bool? valueOf(String field) => switch (field) {
    'chestPain' => chestPain,
    'dizziness' => dizziness,
    'supervisedOnly' => supervisedOnly,
    _ => throw ArgumentError.value(field, 'field'),
  };

  /// Ticks or unticks [value], keeping card order. Any tick clears None.
  HealthAnswers toggle(String value) {
    final on = conditions.contains(value);
    return _copy(
      conditions: [
        for (final c in healthConditions)
          if (c.value == value ? !on : conditions.contains(c.value)) c.value,
      ],
      noneOfThese: false,
    );
  }

  /// "None of these" is exclusive: ticking it clears every condition.
  HealthAnswers toggleNone() =>
      _copy(conditions: const [], noneOfThese: !noneOfThese);

  HealthAnswers answer(String field, bool yes) => switch (field) {
    'chestPain' => _copy(chestPain: yes),
    'dizziness' => _copy(dizziness: yes),
    'supervisedOnly' => _copy(supervisedOnly: yes),
    _ => throw ArgumentError.value(field, 'field'),
  };

  HealthAnswers withAcknowledged(bool value) => _copy(acknowledged: value);
  HealthAnswers withConsent(bool value) => _copy(consent: value);
  HealthAnswers withOptedOut(bool value) => _copy(optedOut: value);

  /// The PUT /profile/health body.
  Map<String, dynamic> toJson() => {
    'conditions': conditions,
    'chestPain': chestPain,
    'dizziness': dizziness,
    'supervisedOnly': supervisedOnly,
    'consent': consent,
    'acknowledged': acknowledged,
  };

  // A question is never un-answered, so `??` is enough for the nullable bools.
  HealthAnswers _copy({
    List<String>? conditions,
    bool? noneOfThese,
    bool? chestPain,
    bool? dizziness,
    bool? supervisedOnly,
    bool? acknowledged,
    bool? consent,
    bool? optedOut,
  }) => HealthAnswers(
    conditions: conditions ?? this.conditions,
    noneOfThese: noneOfThese ?? this.noneOfThese,
    chestPain: chestPain ?? this.chestPain,
    dizziness: dizziness ?? this.dizziness,
    supervisedOnly: supervisedOnly ?? this.supervisedOnly,
    acknowledged: acknowledged ?? this.acknowledged,
    consent: consent ?? this.consent,
    optedOut: optedOut ?? this.optedOut,
  );
}
