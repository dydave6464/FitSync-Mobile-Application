/// The four split styles, and the labels the design gives them.
///
/// One definition rather than one per screen: the generator and the manual
/// setup screen offer the same four, and the `value`s are the slugs the
/// service matches on -- a second copy would let a rename land on one screen
/// and silently send an unknown slug from the other.
const splitStyles = <({String value, String label})>[
  (value: 'full_body', label: 'Full body'),
  (value: 'push_pull_legs', label: 'Push / Pull / Legs'),
  (value: 'upper_lower', label: 'Upper / Lower'),
  (value: 'cardio_core', label: 'Cardio + core'),
];
