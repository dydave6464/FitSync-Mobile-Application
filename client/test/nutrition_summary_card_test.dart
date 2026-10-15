import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_charts.dart' show FsRing;
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/nutrition_summary_card.dart';

NutritionDay _day() => NutritionDay(
  date: '2026-10-14',
  target: const NutritionTarget(kcal: 2100, proteinG: 95, carbsG: 300, fatG: 58, fiberG: 0),
  targetMissing: const [],
  totals: const MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0),
  meals: {for (final m in mealTypes) m: const []},
);

/// A day with sugar and sodium known, for the "More nutrients" row.
NutritionDay _dayWithSugarSodium() => NutritionDay(
  date: '2026-10-14',
  target: const NutritionTarget(kcal: 2100, proteinG: 95, carbsG: 300, fatG: 58, fiberG: 0),
  targetMissing: const [],
  totals: const MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 48.4, sodiumMg: 1850),
  meals: {for (final m in mealTypes) m: const []},
);

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  NutritionDay? day,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    // The Nutrition screen's 20 dp side padding, so the card gets the width
    // it really has on a phone.
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [NutritionSummaryCard(day: day ?? _day())],
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The prototype's card is a row: the ring on the left, the macro bars
/// beside it, filling the rest (screens-nutrition.jsx, `accent-card row`).
void _expectBarsBesideRing(WidgetTester tester) {
  final ring = tester.getRect(find.byType(FsRing));
  for (final label in ['Protein', 'Carbs', 'Fat', 'Fiber']) {
    final bar = tester.getRect(find.text(label));
    expect(bar.left, greaterThan(ring.right), reason: '$label sits to the right of the ring');
  }
  // The column starts level with the ring rather than on a line below it.
  // (At large text the three bars are taller than the ring, so the last one
  // may end lower; only the first has to be level.)
  expect(tester.getRect(find.text('Protein')).top, lessThan(ring.bottom),
      reason: 'the bars start beside the ring, not below it');
}

void main() {
  testWidgets('the macro bars sit beside the ring on a typical phone', (tester) async {
    await _pump(tester, width: 390);
    _expectBarsBesideRing(tester);
  });

  testWidgets('the ring is the prototype size (76)', (tester) async {
    await _pump(tester, width: 390);
    expect(tester.getSize(find.byType(FsRing)), const Size(76, 76));
  });

  testWidgets('a 320 dp phone at large text keeps the row and does not overflow', (tester) async {
    await _pump(tester, width: 320, textScale: 1.6);
    expect(tester.takeException(), isNull);
    _expectBarsBesideRing(tester);
  });

  testWidgets('a 4th bar shows Fiber, beside the ring like the others', (tester) async {
    await _pump(tester, width: 390, day: NutritionDay(
      date: '2026-10-14',
      target: const NutritionTarget(kcal: 2100, proteinG: 95, carbsG: 300, fatG: 58, fiberG: 26),
      targetMissing: const [],
      totals: const MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 12, sugarG: 0, sodiumMg: 0),
      meals: {for (final m in mealTypes) m: const []},
    ));
    expect(find.text('Fiber'), findsOneWidget);
    expect(find.text('12 / 26 g'), findsOneWidget);
    _expectBarsBesideRing(tester);
  });

  testWidgets('Fiber shows just the total when there is no target', (tester) async {
    await _pump(tester, width: 390, day: NutritionDay(
      date: '2026-10-14',
      target: null,
      targetMissing: const ['sex'],
      totals: const MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 12, sugarG: 0, sodiumMg: 0),
      meals: {for (final m in mealTypes) m: const []},
    ));
    expect(find.text('12 g'), findsOneWidget);
  });

  testWidgets('More nutrients is folded by default', (tester) async {
    await _pump(tester, width: 390, day: _dayWithSugarSodium());
    expect(find.text('More nutrients'), findsOneWidget);
    expect(find.byKey(const Key('nutrition.moreNutrients.body')), findsNothing);
    expect(find.text('Sugar'), findsNothing);
  });

  testWidgets('tapping More nutrients reveals sugar and sodium, tapping again hides them', (tester) async {
    await _pump(tester, width: 390, day: _dayWithSugarSodium());

    await tester.tap(find.byKey(const Key('nutrition.moreNutrients')));
    await tester.pumpAndSettle();
    expect(find.text('Sugar'), findsOneWidget);
    expect(find.text('48 g'), findsOneWidget);
    expect(find.text('Sodium'), findsOneWidget);
    expect(find.text('1,850 mg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nutrition.moreNutrients')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrition.moreNutrients.body')), findsNothing);
    expect(find.text('Sugar'), findsNothing);
  });

  testWidgets('More nutrients announces itself as a button with an expanded state', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, width: 390, day: _dayWithSugarSodium());

    expect(
      tester.getSemantics(find.byKey(const Key('nutrition.moreNutrients'))),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
    );

    await tester.tap(find.byKey(const Key('nutrition.moreNutrients')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('nutrition.moreNutrients'))),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
    );

    handle.dispose();
  });

  testWidgets('More nutrients has a tap target at least 44dp tall', (tester) async {
    await _pump(tester, width: 390, day: _dayWithSugarSodium());
    expect(tester.getSize(find.byKey(const Key('nutrition.moreNutrients'))).height, greaterThanOrEqualTo(44));
  });

  testWidgets('with reduced motion, the body appears after a single pump following the tap', (tester) async {
    await _pump(tester, width: 390, day: _dayWithSugarSodium(), disableAnimations: true);

    await tester.tap(find.byKey(const Key('nutrition.moreNutrients')));
    await tester.pump();

    expect(find.byKey(const Key('nutrition.moreNutrients.body')), findsOneWidget);
    expect(find.text('Sugar'), findsOneWidget);
  });

  testWidgets('a 320 dp phone at large text shows More nutrients open without overflow, bars unchanged', (
    tester,
  ) async {
    await _pump(tester, width: 320, textScale: 1.6, day: _dayWithSugarSodium());

    await tester.tap(find.byKey(const Key('nutrition.moreNutrients')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectBarsBesideRing(tester);
  });
}
