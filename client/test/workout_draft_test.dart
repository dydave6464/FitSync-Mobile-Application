import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/sessions/presentation/workout_draft.dart';

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

/// A catalogue row as the library hands it to the draft.
ExerciseSummary _exercise(int id) => ExerciseSummary(
      exerciseId: id,
      name: 'Exercise $id',
      muscleGroup: 'chest',
      equipment: 'barbell',
      thumbnailUrl: null,
    );

/// The ids, in order -- what `POST /sessions` is actually sent.
List<int> _ids(ProviderContainer c) =>
    c.read(workoutDraftProvider).map((e) => e.exerciseId).toList();

void main() {
  test('starts empty', () {
    expect(_container().read(workoutDraftProvider), isEmpty);
  });

  test('toggling adds an exercise', () {
    final c = _container();

    c.read(workoutDraftProvider.notifier).toggle(_exercise(101));

    expect(_ids(c), [101]);
  });

  test('the draft carries the whole row, not just the id', () {
    // The review screen renders names and thumbnails from this, and the user
    // may have scrolled or re-filtered the library away from the page a pick
    // came from -- so the draft cannot rely on the list still holding it.
    final c = _container();

    c.read(workoutDraftProvider.notifier).toggle(_exercise(101));

    expect(c.read(workoutDraftProvider).single.name, 'Exercise 101');
  });

  test('toggling the same exercise again removes it', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(_exercise(101));
    draft.toggle(_exercise(101));

    expect(c.read(workoutDraftProvider), isEmpty);
  });

  test('keeps the order they were picked in', () {
    // A list, not a set: the server writes order_no from this order and the
    // logger walks it, so "chest first" is a choice the user made.
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(_exercise(303));
    draft.toggle(_exercise(101));
    draft.toggle(_exercise(202));

    expect(_ids(c), [303, 101, 202]);
  });

  test('removing from the middle leaves the rest in order', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(_exercise(303));
    draft.toggle(_exercise(101));
    draft.toggle(_exercise(202));
    draft.toggle(_exercise(101));

    expect(_ids(c), [303, 202]);
  });

  test('re-adding puts it at the end, not back where it was', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(_exercise(303));
    draft.toggle(_exercise(101));
    draft.toggle(_exercise(303));
    draft.toggle(_exercise(303));

    expect(_ids(c), [101, 303]);
  });

  test('removing by id takes that exercise out', () {
    // The review screen removes by identity rather than by toggling, so a
    // double tap there cannot silently re-add what was just dropped.
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);
    draft.toggle(_exercise(303));
    draft.toggle(_exercise(101));

    draft.remove(303);
    draft.remove(303);

    expect(_ids(c), [101]);
  });

  test('dragging an exercise down lands it at the new index', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);
    draft.toggle(_exercise(1));
    draft.toggle(_exercise(2));
    draft.toggle(_exercise(3));

    // ReorderableListView's onReorderItem reports the destination already
    // adjusted for the lifted row, so dragging the first row to the bottom of
    // three arrives as newIndex 2.
    draft.reorder(0, 2);

    expect(_ids(c), [2, 3, 1]);
  });

  test('dragging an exercise up lands it at the new index', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);
    draft.toggle(_exercise(1));
    draft.toggle(_exercise(2));
    draft.toggle(_exercise(3));

    draft.reorder(2, 0);

    expect(_ids(c), [3, 1, 2]);
  });

  test('clearing empties it', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);
    draft.toggle(_exercise(101));

    draft.clear();

    expect(c.read(workoutDraftProvider), isEmpty);
  });

  test('reports whether an exercise is in the draft', () {
    final c = _container();
    c.read(workoutDraftProvider.notifier).toggle(_exercise(101));

    expect(c.read(workoutDraftProvider).holds(101), isTrue);
    expect(c.read(workoutDraftProvider).holds(999), isFalse);
  });
}
