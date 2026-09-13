import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/domain/week_description.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/profile/domain/profile.dart';

/// A catalogue shaped like the real one: a lateral region, a non-lateral
/// region, and a two-word name, so matching cannot pass by looking only at
/// single words.
const _options = [
  InjuryOption(injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'leg'),
  InjuryOption(
      injuryId: 9, name: 'Lower back', isLateral: false, regionGroup: 'back'),
  InjuryOption(
      injuryId: 4, name: 'Shoulder', isLateral: true, regionGroup: 'arm'),
];

WeekDescription _parse(String text) => parseWeekDescription(text, _options);

void main() {
  group('days per week', () {
    test('reads a digit beside the word days', () {
      expect(_parse('train 4 days a week').daysPerWeek, 4);
    });

    test('reads a number word', () {
      expect(_parse('I want to train four days').daysPerWeek, 4);
    });

    test('reads the times-a-week form', () {
      expect(_parse('lifting 5x a week').daysPerWeek, 5);
    });

    test('ignores a number that is not counting days', () {
      // The prototype's own example sentence says "~50 min". Reading that as
      // fifty days -- or as five -- is worse than reading nothing.
      expect(_parse('sessions of ~50 min').daysPerWeek, isNull);
    });

    test('clamps a count above seven', () {
      expect(_parse('train 40 days a week').daysPerWeek, 7);
    });

    test('clamps a count below one', () {
      // parameters.derive clamps to the same floor, so a plan of zero days
      // is not something the generator can be asked for.
      expect(_parse('train 0 days a week').daysPerWeek, 1);
    });
  });

  group('split style', () {
    test('reads full body', () {
      expect(_parse('just full body please').splitStyle, 'full_body');
    });

    test('reads push pull legs written with slashes', () {
      expect(_parse('push / pull / legs').splitStyle, 'push_pull_legs');
    });

    test('reads ppl', () {
      expect(_parse('a ppl week').splitStyle, 'push_pull_legs');
    });

    test('reads upper lower', () {
      expect(_parse('upper / lower split').splitStyle, 'upper_lower');
    });

    test('reads cardio and core', () {
      expect(_parse('mostly cardio and core').splitStyle, 'cardio_core');
    });

    test('is case insensitive', () {
      expect(_parse('FULL BODY').splitStyle, 'full_body');
    });

    test('reads nothing from a sentence naming no split', () {
      expect(_parse('I want to train hard').splitStyle, isNull);
    });
  });

  group('injuries', () {
    test('matches a catalogue name and its side', () {
      final injuries = _parse('protect my right knee').injuries;
      expect(injuries, hasLength(1));
      expect(injuries.single.injuryId, 3);
      expect(injuries.single.side, 'right');
    });

    test('matches a two-word name', () {
      final injuries = _parse('careful with my lower back').injuries;
      expect(injuries.single.injuryId, 9);
    });

    test('carries no side for a non-lateral region', () {
      // The server rejects a side on a region that has none, and isLateral
      // is what says so -- never a guess from the region group.
      expect(_parse('my right lower back hurts').injuries.single.side, isNull);
    });

    test('reads both sides', () {
      expect(_parse('both shoulders are sore').injuries.single.side, 'both');
    });

    test('leaves the side null when the text names none', () {
      expect(_parse('my knee is bad').injuries.single.side, isNull);
    });

    test('matches more than one region', () {
      final injuries = _parse('protect my lower back and right knee').injuries;
      expect(injuries.map((i) => i.injuryId), containsAll(<int>[9, 3]));
    });

    test('reads nothing from a sentence naming no region', () {
      expect(_parse('train me hard').injuries, isEmpty);
    });
  });

  group('topics this screen does not own', () {
    test('notices a session length', () {
      expect(_parse('about 50 min a session').elsewhere,
          contains(WeekTopic.sessionLength));
    });

    test('notices a goal', () {
      expect(_parse('I want to gain muscle').elsewhere,
          contains(WeekTopic.goal));
    });

    test('names nothing when the sentence raises neither', () {
      expect(_parse('full body, 4 days a week').elsewhere, isEmpty);
    });
  });

  group('nothing to read', () {
    test('empty text resolves to nothing at all', () {
      final parsed = _parse('');
      expect(parsed.splitStyle, isNull);
      expect(parsed.daysPerWeek, isNull);
      expect(parsed.injuries, isEmpty);
      expect(parsed.isEmpty, isTrue);
    });

    test('a sentence it cannot read resolves to nothing at all', () {
      // "Understood nothing" has to stay distinguishable from "understood
      // full body", or applying a vague sentence would silently reset the
      // controls to defaults.
      expect(_parse('asdf qwer zxcv').isEmpty, isTrue);
    });
  });

  group('composing from what the user already has', () {
    const plan = WorkoutPlan(
      planId: 1,
      name: 'Week 1',
      splitStyle: 'push_pull_legs',
      daysPerWeek: 4,
      sessionLengthMin: 60,
      weekNo: 1,
      days: [],
      exercises: [],
    );

    Profile profileWith({String? goal, List<SelectedInjury> injuries = const []}) =>
        Profile(
          userId: 1,
          email: 'a@b.c',
          fullName: 'Test',
          onboardingCompleted: true,
          isPremium: false,
          notificationsEnabled: true,
          equipment: const [],
          injuries: injuries,
          mainGoal: goal,
        );

    test('names the goal, the days and the split', () {
      final text = composeWeekDescription(
        profile: profileWith(goal: 'build_muscle'),
        plan: plan,
        options: _options,
      );
      expect(text, contains('build muscle'));
      expect(text, contains('4 days'));
      expect(text, contains('push / pull / legs'));
    });

    test('names the injuries being protected, with their sides', () {
      final text = composeWeekDescription(
        profile: profileWith(
          goal: 'build_muscle',
          injuries: const [SelectedInjury(injuryId: 3, side: 'right')],
        ),
        plan: plan,
        options: _options,
      );
      // The catalogue's own casing, not lowercased to fit the sentence:
      // "si joint" beside a non-lateral "Lower back" is the inconsistency
      // injuryLabel exists to avoid.
      expect(text, contains('Knee (right)'));
    });

    test('omits what it does not know rather than inventing it', () {
      final text = composeWeekDescription(
        profile: profileWith(),
        plan: null,
        options: _options,
      );
      expect(text, isNot(contains('null')));
      expect(text, isNot(contains('days')));
    });

    test('what it writes reads back as the same plan', () {
      // The round trip is the point: From profile must not produce a
      // sentence that Apply then resolves into different controls.
      final text = composeWeekDescription(
        profile: profileWith(goal: 'build_muscle'),
        plan: plan,
        options: _options,
      );
      final parsed = parseWeekDescription(text, _options);
      expect(parsed.splitStyle, 'push_pull_legs');
      expect(parsed.daysPerWeek, 4);
    });
  });
}
