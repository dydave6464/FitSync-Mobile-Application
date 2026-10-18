import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsRing;
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/nutrition_summary_card.dart';

/// The real face, not the test harness's: whether "/ 2,050 kcal" clears the
/// ring's stroke depends on how wide Space Grotesk draws it. Kept in its own
/// file so the rest of the Nutrition tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

NutritionDay _day({required int eaten, required int target}) => NutritionDay(
  date: '2026-10-19',
  target: NutritionTarget(
    kcal: target,
    proteinG: 95,
    carbsG: 300,
    fatG: 58,
    fiberG: 25,
  ),
  targetMissing: const [],
  totals: MacroTotals(
    kcal: eaten,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
    fiberG: 0,
    sugarG: 0,
    sodiumMg: 0,
  ),
  meals: {for (final m in mealTypes) m: const []},
);

/// The drawn words of [text], as global corners: where the glyphs land,
/// after any scaling, whatever box the Text widget was given.
List<Offset> _corners(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ),
      )
      .map((b) => b.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return [
    box.topLeft,
    box.topRight,
    box.bottomLeft,
    box.bottomRight,
  ].map(paragraph.localToGlobal).toList();
}

/// The font size [text] is drawn at: its own size, times the system text
/// scale, times whatever its FittedBox shrank it by.
double _drawnSize(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final fit =
      (paragraph.localToGlobal(const Offset(1, 0)) -
              paragraph.localToGlobal(Offset.zero))
          .dx;
  return paragraph.text.style!.fontSize! * paragraph.textScaler.scale(1) * fit;
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  // Both lines sit inside the ring's clear middle, not on its stroke: the
  // label "/ 2,050 kcal" ran into the ring on a phone.
  for (final scale in [1.0, 1.3, 2.0]) {
    // Wide numbers press on the width; a fresh day's "0" fits the width at
    // any size and presses on the height instead.
    for (final (eaten, shown, target) in [
      (1234, '1,234', 2050),
      (2345, '2,345', 3500),
      (0, '0', 2050),
    ]) {
      testWidgets('the ring\'s words clear its stroke: $eaten / $target at '
          '${scale}x', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            theme: fsLightTheme(),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  NutritionSummaryCard(
                    day: _day(eaten: eaten, target: target),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final ring = tester.widget<FsRing>(find.byType(FsRing));
        final centre = tester.getRect(find.byType(FsRing)).center;
        final clear = ring.size / 2 - ring.stroke;

        final eatenText = find.descendant(
          of: find.byType(FsRing),
          matching: find.text(shown),
        );
        final label = find.descendant(
          of: find.byType(FsRing),
          matching: find.textContaining('kcal'),
        );
        for (final (name, text) in [('eaten', eatenText), ('label', label)]) {
          for (final corner in _corners(tester, text)) {
            final d = (corner - centre).distance;
            expect(
              d,
              lessThanOrEqualTo(clear),
              reason:
                  '$name corner $corner is ${d.toStringAsFixed(1)} dp from '
                  'the centre; the clear middle ends at $clear',
            );
          }
        }
        // And still big enough to read, as drawn: the label stays near the
        // prototype's 8 px, and a four-digit total eases but stays large.
        if (target != 0) {
          expect(_drawnSize(tester, label), greaterThanOrEqualTo(7.5));
        }
        if (scale == 1.0 && shown.length >= 5) {
          expect(_drawnSize(tester, eatenText), greaterThanOrEqualTo(16));
        }
      });
    }
  }
}
