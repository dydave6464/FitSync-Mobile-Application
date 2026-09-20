import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/presentation/widgets/ai_cue_list.dart';

Widget _host(Widget child) => MaterialApp(
  theme: fsLightTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

const _ai = ExerciseCues(
  source: 'ai',
  injuryName: 'Shoulder',
  cues: [
    Cue(
      title: 'Pull to the navel',
      detail: 'Keeps the shoulder out of the arc.',
    ),
    Cue(
      title: 'Stop at the ribs',
      detail: 'Past that the joint takes the load.',
    ),
  ],
);

const _catalogue = ExerciseCues(
  source: 'catalogue',
  injuryName: null,
  cues: [Cue(title: 'Brace before you press.')],
);

void main() {
  group('the model', () {
    test('reads the endpoint envelope', () {
      final cues = ExerciseCues.fromJson({
        'source': 'ai',
        'injury': {
          'injuryId': 1,
          'name': 'Shoulder',
          'reason': 'shoulder_load',
        },
        'cues': [
          {'title': 'Pull to the navel', 'detail': 'Keeps it out of the arc.'},
        ],
      });

      expect(cues.isAi, isTrue);
      expect(cues.injuryName, 'Shoulder');
      expect(cues.cues.single.detail, 'Keeps it out of the arc.');
    });

    test('a catalogue cue has no detail and no injury', () {
      final cues = ExerciseCues.fromJson({
        'source': 'catalogue',
        'injury': null,
        'cues': [
          {'title': 'Brace before you press.', 'detail': null},
        ],
      });

      expect(cues.isAi, isFalse);
      expect(cues.injuryName, isNull);
      expect(cues.cues.single.detail, isNull);
    });

    // A response missing fields must not crash a workout screen.
    test('a malformed payload degrades to nothing rather than throwing', () {
      final cues = ExerciseCues.fromJson(const {});
      expect(cues.isAi, isFalse);
      expect(cues.cues, isEmpty);
    });
  });

  testWidgets('numbers the cues the way the mockup does', (tester) async {
    await tester.pumpWidget(_host(const AiCueList(cues: _ai)));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Pull to the navel'), findsOneWidget);
    expect(find.text('Keeps the shoulder out of the arc.'), findsOneWidget);
  });

  // The pill is the honest half of "for your profile": it names the reason
  // these cues differ from everyone else's.
  testWidgets('names the injury the cues were written for', (tester) async {
    await tester.pumpWidget(_host(const AiCueList(cues: _ai)));

    expect(find.text('AI coaching cues'), findsOneWidget);
    expect(find.text('Shoulder'), findsOneWidget);
  });

  // Claiming "AI coaching cues" over the catalogue's own seeded text would be
  // a lie the user has no way to check.
  testWidgets('catalogue cues claim nothing about AI', (tester) async {
    await tester.pumpWidget(_host(const AiCueList(cues: _catalogue)));

    expect(find.text('How to perform'), findsOneWidget);
    expect(find.text('AI coaching cues'), findsNothing);
    expect(find.text('Brace before you press.'), findsOneWidget);
  });

  testWidgets('a cue with no detail renders its title alone', (tester) async {
    await tester.pumpWidget(_host(const AiCueList(cues: _catalogue)));

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an exercise with no cues renders nothing at all', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AiCueList(
          cues: ExerciseCues(source: 'catalogue', injuryName: null, cues: []),
        ),
      ),
    );

    expect(find.text('How to perform'), findsNothing);
    expect(find.text('AI coaching cues'), findsNothing);
  });
}
