/// One coaching cue.
///
/// [detail] is null for a catalogue cue, which is a single sentence with
/// nothing to expand on. The card renders the title alone in that case, so the
/// two sources share one shape rather than two layouts.
class Cue {
  const Cue({required this.title, this.detail});

  final String title;
  final String? detail;

  factory Cue.fromJson(Map<String, dynamic> json) => Cue(
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String?,
      );
}

/// What `GET /exercises/:id/cues` answers.
///
/// [source] is `'ai'` when these were written for [injuryName], and
/// `'catalogue'` when they are the seeded cues every user of this exercise
/// sees. The screen must not claim the first while holding the second --
/// the user has no way to check, so the distinction is ours to keep honest.
class ExerciseCues {
  const ExerciseCues({
    required this.source,
    required this.injuryName,
    required this.cues,
  });

  final String source;
  final String? injuryName;
  final List<Cue> cues;

  bool get isAi => source == 'ai';

  /// The cues an exercise carries on its own, before any generation.
  ///
  /// The demo stage renders these on its first frame from the detail it has
  /// already fetched, so a cue list is on screen while `/cues` is still in
  /// flight -- and a request that never resolves costs the reader nothing.
  factory ExerciseCues.catalogue(List<String> cues) => ExerciseCues(
        source: 'catalogue',
        injuryName: null,
        cues: [for (final cue in cues) Cue(title: cue)],
      );

  /// Defaults over a missing field rather than throwing: a malformed payload
  /// must not take a workout screen down with it.
  factory ExerciseCues.fromJson(Map<String, dynamic> json) => ExerciseCues(
        source: json['source'] as String? ?? 'catalogue',
        injuryName:
            (json['injury'] as Map<String, dynamic>?)?['name'] as String?,
        cues: ((json['cues'] as List<dynamic>?) ?? const [])
            .map((e) => Cue.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}
