import 'workout_plan.dart' show describeSplit;

/// The four split styles, and the labels the design gives them.
///
/// One definition rather than one per screen: the generator and the
/// make-your-plan sheet offer the same four, and the `value`s are the slugs the
/// service matches on -- a second copy would let a rename land on one screen
/// and silently send an unknown slug from the other.
const splitStyles = <({String value, String label})>[
  (value: 'full_body', label: 'Full body'),
  (value: 'push_pull_legs', label: 'Push / Pull / Legs'),
  (value: 'upper_lower', label: 'Upper / Lower'),
  (value: 'cardio_core', label: 'Cardio + core'),
];

/// How a split is named on screen: the choosers' label for one of
/// [splitStyles], and a readable slug ([describeSplit]) for any other value
/// the generator returns. Every screen that names a plan's split asks here,
/// so one split never has two spellings.
String splitLabel(String slug) =>
    offeredSplitLabel(slug) ?? describeSplit(slug);

/// The choosers' label for one of [splitStyles], or null for any other value
/// (or none): the one lookup [splitLabel] and the week sentence share.
String? offeredSplitLabel(String? slug) {
  for (final s in splitStyles) {
    if (s.value == slug) return s.label;
  }
  return null;
}
