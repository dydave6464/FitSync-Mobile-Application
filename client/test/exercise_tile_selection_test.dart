import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_labels.dart';
import 'package:fitsync/features/exercises/presentation/exercise_thumb.dart';
import 'package:fitsync/features/exercises/presentation/widgets/exercise_tile.dart';

const _exercise = ExerciseSummary(
  exerciseId: 101,
  name: 'Incline DB Press',
  muscleGroup: 'pectorals',
  equipment: 'Dumbbell',
  thumbnailUrl: null,
);

const _risky = ExerciseSummary(
  exerciseId: 202,
  name: 'Barbell Deadlift',
  muscleGroup: 'glutes',
  equipment: 'Barbell',
  thumbnailUrl: null,
  contraindicated: true,
);

Future<void> _pump(
  WidgetTester tester, {
  bool selected = false,
  ExerciseSummary exercise = _exercise,
}) => tester.pumpWidget(
  MaterialApp(
    theme: fsLightTheme(),
    home: Scaffold(
      body: ExerciseTile(
        exercise: exercise,
        baseUrl: 'http://test.local',
        onTap: () {},
        selected: selected,
        onInfo: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('an exercise not chosen shows an empty mark', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('tile.select.101')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a chosen exercise is ticked', (tester) async {
    await _pump(tester, selected: true);

    expect(find.byKey(const Key('tile.select.101')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('a screen reader hears whether the row is picked', (
    tester,
  ) async {
    // The tick is drawn, not said: the Recent cards above already say it.
    final handle = tester.ensureSemantics();
    await _pump(tester, selected: true);
    expect(
      tester.getSemantics(find.byType(ListTile)),
      isSemantics(isSelected: true, isButton: true),
    );

    await _pump(tester);
    expect(
      tester.getSemantics(find.byType(ListTile)),
      isSemantics(isSelected: false, isButton: true),
    );
    handle.dispose();
  });

  testWidgets('a picked row is drawn as it always was', (tester) async {
    // ListTile recolours a selected row's words and icons; the tick is what
    // shows a pick here, so the rest of the row stays as it is.
    Future<(Color?, Color?, Color?)> colours({required bool selected}) async {
      await _pump(tester, selected: selected);
      final title = tester.widget<RichText>(
        find.descendant(
          of: find.text('Incline DB Press'),
          matching: find.byType(RichText),
        ),
      );
      final subtitle = tester.widget<RichText>(
        find.descendant(
          of: find.textContaining('Chest'),
          matching: find.byType(RichText),
        ),
      );
      final thumb = IconTheme.of(
        tester.element(find.byIcon(Icons.fitness_center).first),
      );
      return (title.text.style?.color, subtitle.text.style?.color, thumb.color);
    }

    final plain = await colours(selected: false);
    final picked = await colours(selected: true);
    expect(picked, plain);
  });

  testWidgets('the row draws its exercise with the shared thumb', (
    tester,
  ) async {
    await _pump(tester);

    expect(tester.widget<ExerciseThumb>(find.byType(ExerciseThumb)).size, 56);
  });

  testWidgets('an exercise that loads a reported injury is marked', (
    tester,
  ) async {
    // The generator refuses these outright. Someone picking by hand should at
    // least be told, rather than discovering it from their back.
    await _pump(tester, selected: false, exercise: _risky);

    expect(find.byKey(const Key('tile.risk.202')), findsOneWidget);
  });

  testWidgets('a safe exercise carries no warning', (tester) async {
    await _pump(tester, selected: false);

    expect(find.byKey(const Key('tile.risk.101')), findsNothing);
  });

  // The warning shared one ellipsized line with the muscle and equipment, so
  // at 1.0x it pushed them out and at large text it was itself cut short:
  // the safety reason lost exactly for those who need it (SE-7).
  group('the injury warning has a line of its own', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('uncut at ${scale}x on a 360 dp phone', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MaterialApp(
              theme: fsLightTheme(),
              home: Scaffold(
                body: ListView(
                  children: [
                    ExerciseTile(
                      exercise: _risky,
                      baseUrl: 'http://test.local',
                      onTap: () {},
                      selected: false,
                      onInfo: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        final warning = find.text('Loads an injury you reported');
        expect(warning, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(warning).didExceedMaxLines,
          isFalse,
        );
        // Muscle and equipment keep a line of their own, not the warning's:
        // found whole as a text of its own, so nothing shares it.
        final line = find.text(
          '${muscleLabel('glutes')} · ${equipmentLabel('Barbell')}',
        );
        expect(line, findsOneWidget);
        // Uncut at 1.0x. At 2x the test font draws every glyph a full em
        // wide, so this pair is cut there even on two lines; the wrap is
        // checked below with a pair short enough for that font.
        if (scale == 1.0) {
          expect(
            tester.renderObject<RenderParagraph>(line).didExceedMaxLines,
            isFalse,
          );
        }
      });
    }
  });

  // At 2x text on a narrow phone the line was one ellipsized line, so the
  // equipment -- what the library filters by -- was the part cut. A short
  // pair, so it fits two lines even in the test font's full-em glyphs.
  for (final contraindicated in [false, true]) {
    testWidgets('muscle and equipment wrap to a second line at 2x on a 360 dp '
        'phone${contraindicated ? ', under the injury warning' : ''}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            theme: fsLightTheme(),
            home: Scaffold(
              body: ListView(
                children: [
                  ExerciseTile(
                    exercise: ExerciseSummary(
                      exerciseId: 7,
                      name: 'Neck curl',
                      muscleGroup: 'levator scapulae',
                      equipment: 'band',
                      thumbnailUrl: null,
                      contraindicated: contraindicated,
                    ),
                    baseUrl: 'http://test.local',
                    onTap: () {},
                    selected: false,
                    onInfo: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final line = find.text(
        '${muscleLabel('levator scapulae')} · ${equipmentLabel('band')}',
      );
      expect(
        tester.renderObject<RenderParagraph>(line).didExceedMaxLines,
        isFalse,
        reason: 'the equipment was cut',
      );
    });
  }
}
