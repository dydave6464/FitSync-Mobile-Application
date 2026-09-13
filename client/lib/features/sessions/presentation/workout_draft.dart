import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The exercises chosen for a manual workout, before it is started.
///
/// A list rather than a set, because the order is a choice the user made:
/// `POST /sessions` writes `order_no` from this order and the logger walks
/// it. Collapsing it into a set would silently reshuffle their session.
///
/// Lives in the sessions feature rather than the exercises one: the library
/// only renders it, while what it means -- the shape of a workout about to
/// start -- belongs here.
class WorkoutDraftNotifier extends Notifier<List<int>> {
  @override
  List<int> build() => const [];

  /// Adds the exercise, or removes it if it is already chosen.
  ///
  /// Re-adding appends rather than restoring the old position: the list is
  /// the order of picking, and a removed exercise was un-picked.
  void toggle(int exerciseId) {
    state = state.contains(exerciseId)
        ? [
            for (final id in state)
              if (id != exerciseId) id,
          ]
        : [...state, exerciseId];
  }

  void clear() => state = const [];
}

final workoutDraftProvider =
    NotifierProvider<WorkoutDraftNotifier, List<int>>(WorkoutDraftNotifier.new);
