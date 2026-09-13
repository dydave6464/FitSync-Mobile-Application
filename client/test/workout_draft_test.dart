import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/sessions/presentation/workout_draft.dart';

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('starts empty', () {
    expect(_container().read(workoutDraftProvider), isEmpty);
  });

  test('toggling adds an exercise', () {
    final c = _container();

    c.read(workoutDraftProvider.notifier).toggle(101);

    expect(c.read(workoutDraftProvider), [101]);
  });

  test('toggling the same exercise again removes it', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(101);
    draft.toggle(101);

    expect(c.read(workoutDraftProvider), isEmpty);
  });

  test('keeps the order they were picked in', () {
    // A list, not a set: the server writes order_no from this order and the
    // logger walks it, so "chest first" is a choice the user made.
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(303);
    draft.toggle(101);
    draft.toggle(202);

    expect(c.read(workoutDraftProvider), [303, 101, 202]);
  });

  test('removing from the middle leaves the rest in order', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(303);
    draft.toggle(101);
    draft.toggle(202);
    draft.toggle(101);

    expect(c.read(workoutDraftProvider), [303, 202]);
  });

  test('re-adding puts it at the end, not back where it was', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);

    draft.toggle(303);
    draft.toggle(101);
    draft.toggle(303);
    draft.toggle(303);

    expect(c.read(workoutDraftProvider), [101, 303]);
  });

  test('clearing empties it', () {
    final c = _container();
    final draft = c.read(workoutDraftProvider.notifier);
    draft.toggle(101);

    draft.clear();

    expect(c.read(workoutDraftProvider), isEmpty);
  });

  test('reports whether an exercise is in the draft', () {
    final c = _container();
    c.read(workoutDraftProvider.notifier).toggle(101);

    expect(c.read(workoutDraftProvider).contains(101), isTrue);
    expect(c.read(workoutDraftProvider).contains(999), isFalse);
  });
}
