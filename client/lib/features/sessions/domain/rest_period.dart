/// One rest between sets, held as the moment it ends.
///
/// Not a count of ticks: a locked phone, a switched app or a late timer can
/// all skip ticks, and a countdown that only moves on them falls behind.
/// Everything here is worked out from [endsAt] against the clock the caller
/// passes in, so it is right whenever it is asked.
class RestPeriod {
  const RestPeriod({required this.endsAt, required this.totalSeconds});

  factory RestPeriod.start(DateTime now, int seconds) => RestPeriod(
    endsAt: now.add(Duration(seconds: seconds)),
    totalSeconds: seconds,
  );

  final DateTime endsAt;

  /// What the ring measures against: the rest as started, or longer once
  /// +30s has pushed the time left past that.
  final int totalSeconds;

  /// Whole seconds left, rounded up: with 0.2 s to go it still reads 0:01,
  /// so 0:00 only ever shows on a rest that is actually over.
  int secondsLeft(DateTime now) {
    final ms = endsAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  bool isOverAt(DateTime now) => !now.isBefore(endsAt);

  /// The ring's sweep: 1 as the rest starts, 0 once it is over.
  double fractionLeft(DateTime now) {
    if (totalSeconds <= 0) return 0;
    final left = endsAt.difference(now).inMilliseconds / (totalSeconds * 1000);
    return left.clamp(0.0, 1.0);
  }

  /// This rest with [seconds] added (or taken, when negative), capped at
  /// [maxSeconds] left. Null when that leaves nothing: a rest cut to zero is
  /// over.
  RestPeriod? adjusted(int seconds, DateTime now, {required int maxSeconds}) {
    var left = endsAt.difference(now) + Duration(seconds: seconds);
    if (left <= Duration.zero) return null;
    final cap = Duration(seconds: maxSeconds);
    if (left > cap) left = cap;
    final leftSeconds = (left.inMilliseconds + 999) ~/ 1000;
    return RestPeriod(
      endsAt: now.add(left),
      totalSeconds: leftSeconds > totalSeconds ? leftSeconds : totalSeconds,
    );
  }
}
