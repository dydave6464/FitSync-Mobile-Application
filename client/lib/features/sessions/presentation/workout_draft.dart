import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/domain/exercise.dart';

/// The exercises chosen for a manual workout, before it is started.
///
/// A list rather than a set, because the order is a choice the user made:
/// `POST /sessions` writes `order_no` from this order and the logger walks
/// it. Collapsing it into a set would silently reshuffle their session.
///
/// Holds whole catalogue rows rather than ids so the review screen can render
/// names, thumbnails and equipment without a fetch per pick. The library
/// already has the row in hand when it is tapped, and by review time the user
/// may have searched or re-filtered the list away from the page a pick came
/// from -- so the list is not somewhere the names can be looked up again.
/// `POST /sessions` is still sent ids; they are mapped at send.
///
/// Lives in the sessions feature rather than the exercises one: the library
/// only renders it, while what it means -- the shape of a workout about to
/// start -- belongs here.
class WorkoutDraftNotifier extends Notifier<List<ExerciseSummary>> {
  @override
  List<ExerciseSummary> build() => const [];

  /// Adds the exercise, or removes it if it is already chosen.
  ///
  /// Re-adding appends rather than restoring the old position: the list is
  /// the order of picking, and a removed exercise was un-picked.
  void toggle(ExerciseSummary exercise) {
    state = state.holds(exercise.exerciseId)
        ? _without(exercise.exerciseId)
        : [...state, exercise];
  }

  /// Takes an exercise out by id, whatever it was doing there.
  ///
  /// The review screen's job, kept separate from [toggle]: a review row's ✕
  /// only ever removes, so a stray second tap cannot put the exercise back
  /// the way toggling would.
  void remove(int exerciseId) => state = _without(exerciseId);

  /// Moves the exercise at [oldIndex] to [newIndex].
  ///
  /// Both indices are as `ReorderableListView.onReorderItem` reports them,
  /// which is to say [newIndex] already accounts for the dragged row being
  /// lifted out. The older `onReorder` callback did not, and needed the
  /// caller to decrement on a downward move; it is deprecated as of Flutter
  /// 3.41 precisely because that adjustment was so easy to omit.
  void reorder(int oldIndex, int newIndex) {
    final next = [...state];
    next.insert(newIndex, next.removeAt(oldIndex));
    state = next;
  }

  void clear() => state = const [];

  List<ExerciseSummary> _without(int exerciseId) => [
        for (final exercise in state)
          if (exercise.exerciseId != exerciseId) exercise,
      ];
}

extension WorkoutDraft on List<ExerciseSummary> {
  /// Whether this exercise is already chosen. By id, not by identity: the same
  /// catalogue row can arrive as two different objects across two fetches.
  bool holds(int exerciseId) =>
      any((exercise) => exercise.exerciseId == exerciseId);

  /// What `POST /sessions` is sent, in the order shown on the review screen.
  List<int> get exerciseIds =>
      [for (final exercise in this) exercise.exerciseId];
}

final workoutDraftProvider =
    NotifierProvider<WorkoutDraftNotifier, List<ExerciseSummary>>(
  WorkoutDraftNotifier.new,
);
