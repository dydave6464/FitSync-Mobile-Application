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

/// Every target set of each exercise in [done], logged, in session [id].
ActiveSession _session(List<PlanExercise> done, {int id = 1}) => ActiveSession(
  sessionId: id,
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
  final burpee = _exercise(5, 'Burpee');
  final mountain = _exercise(6, 'Mountain climber');
  final lunge = _exercise(7, 'Walking lunge');
  final dip = _exercise(8, 'Bench dip');
  final four = [pushUp, squat, row, plank];

  /// The headline for finishing Push-up first in session [id] -- one exercise
  /// done of four, so never halfway and never the end.
  String firstOfFour(int id) => encouragementFor(
    exercises: four,
    index: 0,
    session: _session([pushUp], id: id),
  )!.headline;

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

  group('a finished exercise', () {
    test('has eight different lines, each naming it and its sets', () {
      final lines = {for (var id = 0; id < 8; id++) firstOfFour(id)};
      expect(lines, hasLength(8));
      for (final line in lines) {
        expect(line, contains('Push-up'));
        expect(line, contains('3'));
      }
    });

    test('keeps the original line among them', () {
      expect(
        firstOfFour(0),
        'Push-up done — all 3 sets. Nice work, keep it up!',
      );
    });

    test('reads the same every time it is asked', () {
      expect(firstOfFour(5), firstOfFour(5));
    });

    test('shifts to another line in the next session', () {
      expect(firstOfFour(1), isNot(firstOfFour(2)));
    });

    test('differs from one exercise to the next in a workout', () {
      // Eight exercises, so none of these is halfway or the end -- every
      // headline comes from the same pool and should not repeat.
      final eight = [pushUp, squat, row, plank, burpee, mountain, lunge, dip];
      final headlines = <String>{};
      for (var index = 0; index < eight.length; index++) {
        final message = encouragementFor(
          exercises: eight,
          index: index,
          session: _session([eight[index]]),
        )!;
        headlines.add(message.headline.replaceAll(eight[index].name, '#'));
      }
      expect(headlines, hasLength(8));
    });

    test('points at the next exercise', () {
      final message = encouragementFor(
        exercises: four,
        index: 0,
        session: _session([pushUp]),
      )!;
      expect(message.detail, 'Up next: Split squat');
    });

    test('a one-set exercise is never called "1 sets" or "all 1 sets"', () {
      final single = _exercise(9, 'Burpee', sets: 1);
      for (var id = 0; id < 8; id++) {
        final line = encouragementFor(
          exercises: [single, squat, row, plank],
          index: 0,
          session: _session([single], id: id),
        )!.headline;
        expect(line, contains('Burpee'));
        // The count, not necessarily the word: "Burpee: 1 for 1" is fine.
        expect(line, contains('1'));
        expect(line, isNot(contains('1 sets')));
        expect(line, isNot(contains('all 1')));
        expect(line, isNot(contains('All 1')));
      }
    });

    test('the last exercise with earlier ones open has no next to name', () {
      // Exercise 2 was skipped, so the session is not complete -- but there
      // is nothing after the plank to point at either.
      final message = encouragementFor(
        exercises: four,
        index: 3,
        session: _session([pushUp, row, plank]),
      )!;
      expect(message.headline, contains('Plank'));
      expect(message.detail, isNull);
    });
  });

  group('halfway', () {
    String halfway(int id) => encouragementFor(
      exercises: four,
      index: 1,
      session: _session([pushUp, squat], id: id),
    )!.headline;

    test('has three lines, each giving the count', () {
      final lines = {for (var id = 0; id < 3; id++) halfway(id)};
      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(line, contains('2 of 4'));
      }
      expect(
        lines,
        contains("Halfway there — 2 of 4 exercises done. You're doing great!"),
      );
    });

    test('still points at the next exercise', () {
      final message = encouragementFor(
        exercises: four,
        index: 1,
        session: _session([pushUp, squat]),
      )!;
      expect(message.detail, 'Up next: Inverted row');
    });

    test('rounds up on an odd count', () {
      final five = [...four, burpee];
      // 2 of 5 is not yet halfway; 3 of 5 is.
      expect(
        encouragementFor(
          exercises: five,
          index: 1,
          session: _session([pushUp, squat]),
        )!.headline,
        isNot(contains('2 of 5')),
      );
      expect(
        encouragementFor(
          exercises: five,
          index: 2,
          session: _session([pushUp, squat, row]),
        )!.headline,
        contains('3 of 5'),
      );
    });
  });

  group('every set done', () {
    String done(int id) => encouragementFor(
      exercises: four,
      index: 3,
      session: _session(four, id: id),
    )!.headline;

    test('has three lines, each pointing at Finish', () {
      final lines = {for (var id = 0; id < 3; id++) done(id)};
      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(line, endsWith('Tap Finish session to save it.'));
      }
      expect(
        lines,
        contains(
          'Every set done — great session! Tap Finish session to save it.',
        ),
      );
    });

    test('names nothing next', () {
      final message = encouragementFor(
        exercises: four,
        index: 3,
        session: _session(four),
      )!;
      expect(message.detail, isNull);
    });
  });
}
