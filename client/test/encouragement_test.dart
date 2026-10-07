import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/encouragement.dart';

PlanExercise _exercise(int id, String name, {int sets = 3}) => PlanExercise(
  planExerciseId: id,
  exerciseId: id,
  name: name,
  muscleGroup: 'chest',
  orderNo: id,
  targetSets: sets,
  targetReps: '8-12',
);

/// Every target set of each exercise in [done], logged.
ActiveSession _session(List<PlanExercise> done) => ActiveSession(
  sessionId: 1,
  status: 'in_progress',
  sessionDate: '2026-10-07',
  sets: [
    for (final exercise in done)
      for (var n = 1; n <= exercise.targetSets; n++)
        LoggedSet(exerciseId: exercise.exerciseId, setNumber: n, reps: 10),
  ],
);

void main() {
  final pushUp = _exercise(1, 'Push-up');
  final squat = _exercise(2, 'Split squat');
  final row = _exercise(3, 'Inverted row');
  final plank = _exercise(4, 'Plank');
  final four = [pushUp, squat, row, plank];

  test('nothing to say while the exercise on screen has sets left', () {
    final partial = ActiveSession(
      sessionId: 1,
      status: 'in_progress',
      sessionDate: '2026-10-07',
      sets: const [LoggedSet(exerciseId: 1, setNumber: 1, reps: 10)],
    );
    expect(
      encouragementFor(exercises: four, index: 0, session: partial),
      isNull,
    );
  });

  test('a finished exercise is praised by name and points at the next', () {
    final message = encouragementFor(
      exercises: four,
      index: 0,
      session: _session([pushUp]),
    )!;
    expect(
      message.headline,
      'Push-up done — all 3 sets. Nice work, keep it up!',
    );
    expect(message.detail, 'Up next: Split squat');
  });

  test('a one-set exercise is not called "all 1 sets"', () {
    final single = _exercise(5, 'Burpee', sets: 1);
    final message = encouragementFor(
      exercises: [single, squat, row, plank],
      index: 0,
      session: _session([single]),
    )!;
    expect(message.headline, 'Burpee done — 1 set. Nice work, keep it up!');
  });

  test('the exercise that reaches halfway says so instead', () {
    final message = encouragementFor(
      exercises: four,
      index: 1,
      session: _session([pushUp, squat]),
    )!;
    expect(
      message.headline,
      "Halfway there — 2 of 4 exercises done. You're doing great!",
    );
    expect(message.detail, 'Up next: Inverted row');
  });

  test('halfway rounds up on an odd count', () {
    final five = [...four, _exercise(5, 'Burpee')];
    // 2 of 5 is not yet halfway; 3 of 5 is.
    expect(
      encouragementFor(
        exercises: five,
        index: 1,
        session: _session([pushUp, squat]),
      )!.headline,
      startsWith('Split squat done'),
    );
    expect(
      encouragementFor(
        exercises: five,
        index: 2,
        session: _session([pushUp, squat, row]),
      )!.headline,
      startsWith('Halfway there — 3 of 5'),
    );
  });

  test('every exercise done closes the session out', () {
    final message = encouragementFor(
      exercises: four,
      index: 3,
      session: _session(four),
    )!;
    expect(
      message.headline,
      'Every set done — great session! Tap Finish session to save it.',
    );
    expect(message.detail, isNull);
  });

  test('the last exercise done with earlier ones open has no next to name', () {
    // Exercise 2 was skipped, so the session is not complete -- but there is
    // nothing after the plank to point at either.
    final message = encouragementFor(
      exercises: four,
      index: 3,
      session: _session([pushUp, row, plank]),
    )!;
    expect(message.headline, 'Plank done — all 3 sets. Nice work, keep it up!');
    expect(message.detail, isNull);
  });
}
