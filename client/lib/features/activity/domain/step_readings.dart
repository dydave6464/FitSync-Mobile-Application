/// Android's step sensor gives one running total since the phone last
/// restarted, never a day's count, so the app keeps its own readings and
/// works the day out from them (spec: "Android").
class StepReading {
  const StepReading({
    required this.atMs,
    required this.steps,
    required this.bootMs,
  });

  /// When the reading was taken (epoch ms).
  final int atMs;

  /// The sensor's total since boot.
  final int steps;

  /// When the phone booted (epoch ms). A change means a restart.
  final int bootMs;

  Map<String, Object> toJson() => {'atMs': atMs, 'steps': steps, 'bootMs': bootMs};

  factory StepReading.fromJson(Map<String, dynamic> json) => StepReading(
    atMs: json['atMs'] as int,
    steps: json['steps'] as int,
    bootMs: json['bootMs'] as int,
  );
}

/// Today's count and what the Activity screen should say about it.
class DaySteps {
  const DaySteps({
    required this.steps,
    this.sinceTurnedOn = false,
    this.includesEarlierDays = false,
  });

  final int steps;

  /// No reading before today: counted from when step counting was turned on.
  final bool sinceTurnedOn;

  /// The last reading before today is more than a day old, so steps from
  /// days the app was not opened are in today's count.
  final bool includesEarlierDays;
}

const _dayMs = 86400000;

/// Boot times worked out on the phone jitter by a few milliseconds.
const _bootToleranceMs = 60000;

bool _restarted(StepReading before, StepReading after) =>
    after.steps < before.steps ||
    (after.bootMs - before.bootMs).abs() > _bootToleranceMs;

/// Today's steps: the latest reading minus the last one before [midnightMs],
/// adding the new total on top after a restart.
DaySteps stepsSince(List<StepReading> readings, int midnightMs) {
  final sorted = [...readings]..sort((a, b) => a.atMs.compareTo(b.atMs));
  final before = [for (final r in sorted) if (r.atMs < midnightMs) r];
  final today = [for (final r in sorted) if (r.atMs >= midnightMs) r];
  final chain = [if (before.isNotEmpty) before.last, ...today];
  var total = 0;
  for (var i = 1; i < chain.length; i++) {
    total += _restarted(chain[i - 1], chain[i])
        ? chain[i].steps
        : chain[i].steps - chain[i - 1].steps;
  }
  return DaySteps(
    steps: total,
    sinceTurnedOn: before.isEmpty,
    includesEarlierDays:
        before.isNotEmpty && before.last.atMs < midnightMs - _dayMs,
  );
}

/// The readings still needed: the last before [midnightMs] and all since.
List<StepReading> pruneReadings(List<StepReading> readings, int midnightMs) {
  final sorted = [...readings]..sort((a, b) => a.atMs.compareTo(b.atMs));
  final before = [for (final r in sorted) if (r.atMs < midnightMs) r];
  return [
    if (before.isNotEmpty) before.last,
    for (final r in sorted) if (r.atMs >= midnightMs) r,
  ];
}
