/// The four answers to "any pain since?", in the order the sheet shows them.
///
/// The server's own spellings: session_outcomes.pain_level is an ENUM of
/// exactly these, and the route refuses anything else. A chip may prettify
/// its label; the value posted must be one of these strings untouched.
const painLevels = ['none', 'mild', 'moderate', 'severe'];

/// A completed session the server wants a pain report for, as
/// GET /sessions/pending-outcome returns it.
class PendingOutcome {
  const PendingOutcome({
    required this.sessionId,
    required this.sessionDate,
    required this.planName,
  });

  final int sessionId;

  /// `YYYY-MM-DD`.
  final String sessionDate;
  final String? planName;

  /// The same name the Progress list and the "+" sheet give a session.
  String get title => planName ?? 'Your own workout';

  factory PendingOutcome.fromJson(Map<String, dynamic> json) => PendingOutcome(
    sessionId: json['sessionId'] as int,
    sessionDate: json['sessionDate'] as String,
    planName: json['planName'] as String?,
  );
}
