import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/steps/level_step.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

const _fitnessLevels = ['beginner', 'intermediate'];
const _locations = ['home_gym', 'commercial_gym', 'both', 'other'];

/// Deliberately not the mockup's "Barbell, Dumbbells, Bench". The real
/// `equipment` table was filled by the catalogue seed and its rows may not
/// match the design; the step must render what the server sends.
const _serverEquipment = [
  EquipmentOption(equipmentId: 41, name: 'Resistance band'),
  EquipmentOption(equipmentId: 62, name: 'Sled machine'),
];

Future<LevelAnswers?> _pump(
  WidgetTester tester, {
  LevelAnswers value = const LevelAnswers(),
  List<EquipmentOption>? equipment,
  Future<List<EquipmentOption>>? pending,
}) async {
  LevelAnswers? emitted;
  await tester.pumpWidget(ProviderScope(
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
  ));
  await tester.pumpAndSettle();
  return emitted;
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers exactly two experience levels', (tester) async {
    await _pump(tester);

    for (final value in _fitnessLevels) {
      expect(find.byKey(Key('segment.$value')), findsOneWidget);
    }
  });

  testWidgets('emits the fitness level enum value', (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith((ref) async => _serverEquipment),
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
    ));
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('segment.intermediate'));

    expect(emitted!.fitnessLevel, 'intermediate');
  });

  testWidgets('names the chosen training location on its row', (tester) async {
    await _pump(tester,
        value: const LevelAnswers(trainingLocation: 'commercial_gym'));

    // The design gives location a row at the foot of the screen showing its
    // current value, not a chip strip competing with the equipment set above.
    expect(find.byKey(const Key('trainingLocation')), findsOneWidget);
    expect(find.text('Commercial gym'), findsOneWidget);
    expect(find.byKey(const Key('location.commercial_gym')), findsNothing,
        reason: 'the options live in the picker the row opens, not on the step');
  });

  testWidgets('the location row opens a picker offering exactly four',
      (tester) async {
    await _pump(tester);

    await _tapKey(tester, const Key('trainingLocation'));

    for (final value in _locations) {
      expect(find.byKey(Key('location.$value')), findsOneWidget);
    }
  });

  testWidgets('the picker insets its options from the sheet edge',
      (tester) async {
    await _pump(tester);

    await _tapKey(tester, const Key('trainingLocation'));

    // The app theme gives every ListTile 4dp of horizontal content padding,
    // which suits tiles inside a card that brings its own inset. Dropped
    // straight into a sheet, that leaves the labels against the screen edge.
    // Measured against the sheet's own edge, not the screen's: the test
    // viewport is 800dp wide, so the sheet is capped at 640 and centred, and
    // a screen-relative assertion passes on 80dp of dead margin that no
    // phone ever has.
    final sheetEdge =
        tester.getTopLeft(find.byKey(const Key('location.home_gym'))).dx;
    expect(tester.getTopLeft(find.text('Home gym')).dx - sheetEdge,
        greaterThanOrEqualTo(16.0),
        reason: 'options have to clear the edge the sheet is flush with');
  });

  testWidgets('picking a location emits it and closes the picker',
      (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith((ref) async => _serverEquipment),
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
    ));
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('trainingLocation'));
    await _tapKey(tester, const Key('location.both'));

    expect(emitted!.trainingLocation, 'both');
    expect(find.byKey(const Key('location.both')), findsNothing,
        reason: 'a picker left open would cover the step it just edited');
  });

  testWidgets('renders the equipment the server returned, not the mockup list',
      (tester) async {
    await _pump(tester);

    expect(find.text('Resistance band'), findsOneWidget);
    expect(find.text('Sled machine'), findsOneWidget);
    expect(find.text('Dumbbells'), findsNothing,
        reason: 'the mockup list must not be hard-coded into the step');
  });

  testWidgets('shows a spinner while the equipment lookup is in flight',
      (tester) async {
    final pending = Completer<List<EquipmentOption>>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith((ref) => pending.future),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LevelStep(
              value: const LevelAnswers(),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(_serverEquipment);
    await tester.pumpAndSettle();
  });

  testWidgets('selecting equipment emits the complete id set', (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith((ref) async => _serverEquipment),
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
    ));
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('equipment.62'));

    // The server replaces the whole set, so a delta would silently drop 41.
    expect(emitted!.equipmentIds, containsAll(<int>[41, 62]));
    expect(emitted!.equipmentIds, hasLength(2));
  });

  testWidgets('deselecting equipment emits the remaining set', (tester) async {
    LevelAnswers? emitted;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith((ref) async => _serverEquipment),
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
    ));
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('equipment.41'));

    expect(emitted!.equipmentIds, [62]);
  });

  testWidgets('an empty equipment list shows a fallback message, not blank space',
      (tester) async {
    await _pump(tester, equipment: const []);

    expect(find.text('No equipment options are available right now.'),
        findsOneWidget);
    expect(find.byType(FsChip), findsNothing,
        reason: 'equipment chips are the only chips on this step now, and '
            'there is nothing to render one from');
  });

  for (final scale in [1.5, 2.0]) {
    testWidgets(
        'the equipment eyebrow row does not overflow at ${scale}x text scale '
        'on a narrow screen', (tester) async {
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

      await _pump(tester);

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
      expect(exception, isNull,
          reason: exception == null
              ? null
              : 'a layout overflow appeared on step 3 at ${scale}x/320dp; '
                  'the eyebrow row (Available equipment / N selected) is the '
                  'most likely source, since it is the one Row here with an '
                  'unflexed sibling: $exception');
    });
  }
}
