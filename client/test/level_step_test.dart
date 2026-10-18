import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/steps/level_step.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

const _fitnessLevels = ['new', 'beginner', 'intermediate'];
const _locations = ['home_gym', 'commercial_gym', 'both', 'other'];

/// Deliberately not the mockup's "Barbell, Dumbbells, Bench". The real
/// `equipment` table was filled by the catalogue seed and its rows may not
/// match the design; the step must render what the server sends.
const _serverEquipment = [
  EquipmentOption(equipmentId: 41, name: 'Resistance band'),
  EquipmentOption(equipmentId: 62, name: 'Sled machine'),
];

const _keyedEquipment = [
  EquipmentOption(equipmentId: 1, name: 'Barbell', key: 'barbell'),
  EquipmentOption(equipmentId: 2, name: 'Dumbbells', key: 'dumbbell'),
  EquipmentOption(equipmentId: 3, name: 'Bench', key: 'bench'),
  EquipmentOption(equipmentId: 4, name: 'Pull-up bar', key: 'pull-up bar'),
  EquipmentOption(equipmentId: 5, name: 'Kettlebell', key: 'kettlebell'),
  EquipmentOption(equipmentId: 6, name: 'Bands', key: 'band'),
  EquipmentOption(equipmentId: 7, name: 'Machines', key: 'machines'),
  EquipmentOption(equipmentId: 8, name: 'Bodyweight', key: 'body weight'),
];

Future<LevelAnswers?> _pump(
  WidgetTester tester, {
  LevelAnswers value = const LevelAnswers(),
  List<EquipmentOption>? equipment,
  Future<List<EquipmentOption>>? pending,
}) async {
  LevelAnswers? emitted;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith(
          (ref) => pending ?? Future.value(equipment ?? _serverEquipment),
        ),
      ],
      child: MaterialApp(
        // The real theme, not a bare MaterialApp: its ListTile contentPadding
        // is 4dp, and a default-themed harness silently substitutes Flutter's
        // roomier 16dp — hiding exactly the kind of inset defect this step's
        // picker shipped with.
        theme: fsLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LevelStep(value: value, onChanged: (v) => emitted = v),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return emitted;
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// Picks a location through the sheet, the way a user does.
Future<void> _pickLocation(WidgetTester tester, String value) async {
  await _tapKey(tester, const Key('trainingLocation'));
  await tester.tap(find.byKey(Key('location.$value')));
  await tester.pumpAndSettle();
}

/// Holds the answers between taps, the way the onboarding flow does.
Future<LevelAnswers Function()> _pumpLive(
  WidgetTester tester, {
  LevelAnswers initial = const LevelAnswers(),
}) async {
  var current = initial;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith(
          (ref) => Future.value(_keyedEquipment),
        ),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => LevelStep(
                value: current,
                onChanged: (v) => setState(() => current = v),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => current;
}

void main() {
  testWidgets('offers exactly three experience levels, New to training first', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.descendant(
        of: find.byType(FsSegmented),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(3),
    );
    for (final value in _fitnessLevels) {
      expect(find.byKey(Key('segment.$value')), findsOneWidget);
    }
    expect(find.text('New to training'), findsOneWidget);
  });

  testWidgets('emits the fitness level enum value', (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentOptionsProvider.overrideWith(
            (ref) async => _serverEquipment,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LevelStep(
                value: const LevelAnswers(),
                onChanged: (v) => emitted = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('segment.intermediate'));

    expect(emitted!.fitnessLevel, 'intermediate');
  });

  testWidgets('names the chosen training location on its row', (tester) async {
    await _pump(
      tester,
      value: const LevelAnswers(trainingLocation: 'commercial_gym'),
    );

    // The design gives location a row at the foot of the screen showing its
    // current value, not a chip strip competing with the equipment set above.
    expect(find.byKey(const Key('trainingLocation')), findsOneWidget);
    expect(find.text('Commercial gym'), findsOneWidget);
    expect(
      find.byKey(const Key('location.commercial_gym')),
      findsNothing,
      reason: 'the options live in the picker the row opens, not on the step',
    );
  });

  testWidgets('the location row opens a picker offering exactly four', (
    tester,
  ) async {
    await _pump(tester);

    await _tapKey(tester, const Key('trainingLocation'));

    for (final value in _locations) {
      expect(find.byKey(Key('location.$value')), findsOneWidget);
    }
  });

  testWidgets('the picker insets its options from the sheet edge', (
    tester,
  ) async {
    await _pump(tester);

    await _tapKey(tester, const Key('trainingLocation'));

    // The app theme gives every ListTile 4dp of horizontal content padding,
    // which suits tiles inside a card that brings its own inset. Dropped
    // straight into a sheet, that leaves the labels against the screen edge.
    // Measured against the sheet's own edge, not the screen's: the test
    // viewport is 800dp wide, so the sheet is capped at 640 and centred, and
    // a screen-relative assertion passes on 80dp of dead margin that no
    // phone ever has.
    final sheetEdge = tester
        .getTopLeft(find.byKey(const Key('location.home_gym')))
        .dx;
    expect(
      tester.getTopLeft(find.text('Home gym')).dx - sheetEdge,
      greaterThanOrEqualTo(16.0),
      reason: 'options have to clear the edge the sheet is flush with',
    );
  });

  testWidgets('picking a location emits it and closes the picker', (
    tester,
  ) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentOptionsProvider.overrideWith(
            (ref) async => _serverEquipment,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LevelStep(
                value: const LevelAnswers(),
                onChanged: (v) => emitted = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('trainingLocation'));
    await _tapKey(tester, const Key('location.both'));

    expect(emitted!.trainingLocation, 'both');
    expect(
      find.byKey(const Key('location.both')),
      findsNothing,
      reason: 'a picker left open would cover the step it just edited',
    );
  });

  testWidgets('location is asked before the equipment', (tester) async {
    await _pump(tester, equipment: _keyedEquipment);
    final location = tester
        .getTopLeft(find.byKey(const Key('trainingLocation')))
        .dy;
    final firstChip = tester
        .getTopLeft(find.byKey(const Key('equipment.1')))
        .dy;
    expect(location, lessThan(firstChip));
  });

  for (final (location, ids) in [
    ('commercial_gym', [1, 2, 3, 4, 5, 6, 7]),
    ('both', [1, 2, 3, 4, 5, 6, 7]),
    ('home_gym', [2, 6]),
    ('other', [4, 6, 8]),
  ]) {
    testWidgets(
      'choosing $location with nothing ticked pre-ticks its equipment',
      (tester) async {
        LevelAnswers? emitted;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              equipmentOptionsProvider.overrideWith(
                (ref) => Future.value(_keyedEquipment),
              ),
            ],
            child: MaterialApp(
              theme: fsLightTheme(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: LevelStep(
                    value: const LevelAnswers(),
                    onChanged: (v) => emitted = v,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _pickLocation(tester, location);
        expect(emitted!.trainingLocation, location);
        expect(emitted!.equipmentIds.toSet(), ids.toSet());
      },
    );
  }

  testWidgets('a location never overwrites equipment already ticked', (
    tester,
  ) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentOptionsProvider.overrideWith(
            (ref) => Future.value(_keyedEquipment),
          ),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LevelStep(
                value: const LevelAnswers(equipmentIds: [5]),
                onChanged: (v) => emitted = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pickLocation(tester, 'commercial_gym');
    expect(emitted!.equipmentIds, [5]);
  });

  testWidgets('options without keys pre-tick nothing', (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentOptionsProvider.overrideWith(
            (ref) => Future.value(_serverEquipment),
          ),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LevelStep(
                value: const LevelAnswers(),
                onChanged: (v) => emitted = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pickLocation(tester, 'home_gym');
    expect(emitted!.equipmentIds, isEmpty);
  });

  testWidgets(
    'renders the equipment the server returned, not the mockup list',
    (tester) async {
      await _pump(tester);

      expect(find.text('Resistance band'), findsOneWidget);
      expect(find.text('Sled machine'), findsOneWidget);
      expect(
        find.text('Dumbbells'),
        findsNothing,
        reason: 'the mockup list must not be hard-coded into the step',
      );
    },
  );

  testWidgets('shows a spinner while the equipment lookup is in flight', (
    tester,
  ) async {
    final pending = Completer<List<EquipmentOption>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentOptionsProvider.overrideWith((ref) => pending.future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LevelStep(value: const LevelAnswers(), onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(_serverEquipment);
    await tester.pumpAndSettle();
  });

  testWidgets('selecting equipment emits the complete id set', (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentOptionsProvider.overrideWith(
            (ref) async => _serverEquipment,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LevelStep(
                value: const LevelAnswers(equipmentIds: [41]),
                onChanged: (v) => emitted = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('equipment.62'));

    // The server replaces the whole set, so a delta would silently drop 41.
    expect(emitted!.equipmentIds, containsAll(<int>[41, 62]));
    expect(emitted!.equipmentIds, hasLength(2));
  });

  testWidgets('deselecting equipment emits the remaining set', (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          equipmentOptionsProvider.overrideWith(
            (ref) async => _serverEquipment,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LevelStep(
                value: const LevelAnswers(equipmentIds: [41, 62]),
                onChanged: (v) => emitted = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('equipment.41'));

    expect(emitted!.equipmentIds, [62]);
  });

  testWidgets(
    'an empty equipment list shows a fallback message, not blank space',
    (tester) async {
      await _pump(tester, equipment: const []);

      expect(
        find.text('No equipment options are available right now.'),
        findsOneWidget,
      );
      expect(
        find.byType(FsChip),
        findsNothing,
        reason:
            'equipment chips are the only chips on this step now, and '
            'there is nothing to render one from',
      );
    },
  );

  for (final scale in [1.5, 2.0]) {
    testWidgets(
      'the equipment eyebrow row does not overflow at ${scale}x text scale '
      'on a narrow screen',
      (tester) async {
        // 320dp is a common small-phone width; 2.0x is Android 14's maximum
        // text scale, with 1.5x kept as a lower accessibility point on the
        // same range. Neither the width nor the scale alone forces the
        // overflow this is guarding — it takes the combination.
        tester.view.physicalSize = const Size(320, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        // Keyed equipment at the higher scale too, cheaply: it is what makes
        // the "not familiar" card render, and that card is the step's tallest
        // content, so it belongs in at least one overflow case here.
        await _pump(tester, equipment: scale == 2.0 ? _keyedEquipment : null);

        // A bare takeException() catches any overflow anywhere on the step,
        // not just the eyebrow row's. That is deliberate breadth, not
        // sloppiness: RenderFlex's overflow flag is private
        // (RenderFlex._hasOverflow) with no public accessor, and the
        // FlutterError this throws carries only a generic "overflowed by N
        // pixels" summary — no widget identity or source location — so there
        // is no supported way to attribute the exception to this Row
        // specifically without abandoning exception-based detection (and
        // rendering the eyebrow row in isolation, which would stop this test
        // from also guarding the rest of the step).
        final exception = tester.takeException();
        expect(
          exception,
          isNull,
          reason: exception == null
              ? null
              : 'a layout overflow appeared on step 3 at ${scale}x/320dp; '
                    'the eyebrow row (Available equipment / N selected) is the '
                    'most likely source, since it is the one Row here with an '
                    'unflexed sibling: $exception',
        );
      },
    );
  }

  testWidgets('"New to training" does not truncate at 320dp', (tester) async {
    // 320dp splits the three segments to ~87dp apiece (minus the control's
    // own padding and gaps); "New to training" at 12.5px/w600 needs ~95dp on
    // one line, which used to ellipsize it. The label is a binding
    // constraint and must never be shortened, so it has to wrap instead.
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester);

    expect(find.text('New to training'), findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('New to training'),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason:
          'wrapping to a second line must be enough; it must not need '
          'a third or ellipsize',
    );
  });

  testWidgets('offers "not familiar" with its subtitle', (tester) async {
    await _pumpLive(tester);
    expect(find.text("I'm not familiar with any of these"), findsOneWidget);
    expect(
      find.text("We'll start you on bodyweight exercises."),
      findsOneWidget,
    );
  });

  testWidgets('"not familiar" replaces the ticks with Bodyweight alone', (
    tester,
  ) async {
    final answers = await _pumpLive(
      tester,
      initial: const LevelAnswers(equipmentIds: [1, 2, 7]),
    );
    await _tapKey(tester, const Key('equipment.unfamiliar'));
    expect(answers().equipmentIds, [8]);
    expect(answers().unfamiliar, isTrue);
    // The chips read as unticked while it is the choice.
    expect(
      tester.widget<FsChip>(find.byKey(const Key('equipment.8'))).selected,
      isFalse,
    );
  });

  testWidgets('ticking a chip clears "not familiar" and keeps only that tick', (
    tester,
  ) async {
    final answers = await _pumpLive(tester);
    await _tapKey(tester, const Key('equipment.unfamiliar'));
    await _tapKey(tester, const Key('equipment.2'));
    expect(answers().unfamiliar, isFalse);
    expect(answers().equipmentIds, [2]);
  });

  testWidgets('a location chosen after "not familiar" does not pre-tick', (
    tester,
  ) async {
    final answers = await _pumpLive(tester);
    await _tapKey(tester, const Key('equipment.unfamiliar'));
    await _pickLocation(tester, 'commercial_gym');
    expect(answers().equipmentIds, [8]);
  });

  testWidgets('no Bodyweight option means no "not familiar" choice', (
    tester,
  ) async {
    await _pump(tester); // _serverEquipment: no keys, no Bodyweight
    expect(find.byKey(const Key('equipment.unfamiliar')), findsNothing);
  });

  // What each level does to the plan, said under the selector. The copy
  // describes the kind of change rather than numbers, so it cannot drift from
  // the generator (ml/app/rules/parameters.py), where the numbers depend on
  // the goal too.
  group('the level hint', () {
    const hint = Key('level.hint');
    final cases = {
      // No "change it in Settings": this step is also the Settings editor.
      null: 'Not sure? Pick Beginner.',
      'new': 'The gentlest start: the fewest sets per exercise.',
      'beginner': 'One set fewer than the standard plan.',
      'intermediate': 'The full plan for your goal.',
    };
    for (final entry in cases.entries) {
      testWidgets('for ${entry.key ?? 'no level yet'}', (tester) async {
        await _pump(tester, value: LevelAnswers(fitnessLevel: entry.key));
        await tester.pumpAndSettle();

        expect(tester.widget<Text>(find.byKey(hint)).data, entry.value);
      });
    }

    testWidgets('is readable grey, not the faint caption colour', (
      tester,
    ) async {
      await _pump(tester);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(hint)).style?.color,
        FsTokens.light.text2,
      );
    });
  });

  testWidgets('"not familiar" tells a screen reader whether it is chosen', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpLive(tester);

    final card = find.byKey(const Key('equipment.unfamiliar'));
    expect(
      tester.getSemantics(card),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
    );

    await _tapKey(tester, const Key('equipment.unfamiliar'));
    expect(
      tester.getSemantics(card),
      isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
    );
    handle.dispose();
  });

  // One row of chips is only as tall as a chip: the room around the rows is
  // what takes the outer chips' bands to 48 dp.
  testWidgets('an equipment chip takes a tap just above its pill', (
    tester,
  ) async {
    final current = await _pumpLive(tester);

    final chip = find.byKey(const Key('equipment.1'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(chip).topCenter.translate(0, -7));
    await tester.pumpAndSettle();

    expect(current().equipmentIds, contains(1));
  });
}
