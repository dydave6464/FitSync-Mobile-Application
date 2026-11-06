import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/presentation/add_food_manually_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

Future<FakeNutritionRepository> _pump(WidgetTester tester, {Size? size, double textScale = 1}) async {
  final repo = FakeNutritionRepository();
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Consumer(builder: (context, ref, _) {
        ref.watch(nutritionDayProvider); // loaded, as on the Nutrition tab
        return Scaffold(body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
            builder: (_) => const AddFoodManuallyScreen(mealType: 'snack'),
          )),
          child: const Text('go'),
        ));
      }),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('calories fill in from the macros', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    expect(find.text('198 kcal'), findsOneWidget);
  });

  testWidgets('calories match the server, which rounds each gram to 2 decimals first', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.fat')), '0.0551');
    await tester.pump();
    // 0.0551 -> 0.06 g -> 0.54 kcal -> 1 (unrounded it would show 0).
    expect(find.text('1 kcal'), findsOneWidget);
  });

  testWidgets('Log stays off until there is a name and some macros', (tester) async {
    // Tall enough that every field and the Log button are built at once --
    // this test repeatedly jumps between the top and bottom of the form.
    final repo = await _pump(tester, size: const Size(400, 1200));
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty, reason: 'no macros yet');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '600');
    await tester.pump();
    expect(find.text('Must be 0–500 g'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('log 2026-10-14 snack Turon x1.0'));
    expect(find.text('go'), findsOneWidget, reason: 'back on the screen underneath');
  });

  testWidgets('fiber is optional, logged with the food and never changes kcal', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.fiber')), '4');
    await tester.pump();
    expect(find.text('198 kcal'), findsOneWidget, reason: 'kcal comes from protein, carbs and fat only');
    // `.first` is the screen's outer list; the TextFields above it each own a
    // later Scrollable of their own (for text selection/editing).
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.fiberG, 4);
  });

  testWidgets('blank fiber logs as unknown', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.fiberG, isNull);
  });

  testWidgets('an out-of-range fiber says so and Log stays off', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.fiber')), '600');
    await tester.pump();
    expect(find.text('Must be 0–500 g'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('sugar and sodium are optional, logged with the food and never change kcal', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.sugar')), '4');
    await tester.enterText(find.byKey(const Key('manual.sodium')), '250');
    await tester.pump();
    expect(find.text('198 kcal'), findsOneWidget, reason: 'kcal comes from protein, carbs and fat only');
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.sugarG, 4);
    expect(repo.lastLogged!.sodiumMg, 250);
  });

  testWidgets('blank sugar and sodium log as unknown', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.sugarG, isNull);
    expect(repo.lastLogged!.sodiumMg, isNull);
  });

  testWidgets('an out-of-range sodium says so and Log stays off', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.sodium')), '25000');
    await tester.pump();
    expect(find.text('Must be 0–20,000 mg'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('the Fiber, Sugar and Sodium boxes are labelled and the six boxes fit a 320 dp phone at large text', (tester) async {
    await _pump(tester, size: const Size(320, 900), textScale: 1.6);
    expect(find.text('Fiber (g)'), findsOneWidget);
    expect(find.text('Sugar (g)'), findsOneWidget);
    expect(find.text('Sodium (mg)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('back with something typed (NU-3)', () {
    testWidgets('an empty form leaves without asking', (tester) async {
      await _pump(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('a typed name asks first; Keep editing keeps it', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard.keep')));
      await tester.pumpAndSettle();
      expect(find.text('Turon'), findsOneWidget);
    });

    testWidgets('a typed number asks first; Discard leaves', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    });
  });

  group('number errors (NU-10)', () {
    /// [message] sits right under [field]'s box, inside its width.
    void expectUnder(WidgetTester tester, String field, String message) {
      final box = tester.getRect(find.byKey(Key(field)));
      final error = tester.getRect(find.text(message));
      expect(error.top, greaterThanOrEqualTo(box.bottom));
      expect(error.top - box.bottom, lessThan(24), reason: 'directly under the box');
      expect(error.left, greaterThanOrEqualTo(box.left - 1));
      expect(error.right, lessThanOrEqualTo(box.right + 1));
    }

    testWidgets('an out-of-range number is said under its own box, and announced', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, size: const Size(400, 1200));
      await tester.enterText(find.byKey(const Key('manual.fat')), '600');
      await tester.pump();
      expect(find.text('Must be 0–500 g'), findsOneWidget);
      expectUnder(tester, 'manual.fat', 'Must be 0–500 g');
      expect(
        tester.getSemantics(find.ancestor(of: find.text('Must be 0–500 g'), matching: find.byType(FsErrorLine))),
        isSemantics(isLiveRegion: true),
      );
      // Tied to the box: focusing it says what is wrong.
      final fat = tester.getSemantics(find.byKey(const Key('manual.fat')));
      expect(fat.label, startsWith('Fat (g)'));
      expect(fat.hint, 'Must be 0–500 g');
      expect(fat.flagsCollection.isTextField, isTrue);
      h.dispose();
    });

    testWidgets('an out-of-range sodium is said under the sodium box', (tester) async {
      await _pump(tester, size: const Size(400, 1200));
      await tester.enterText(find.byKey(const Key('manual.sodium')), '25000');
      await tester.pump();
      expectUnder(tester, 'manual.sodium', 'Must be 0–20,000 mg');
    });

    testWidgets('an unreadable number asks for a number, not a range', (tester) async {
      await _pump(tester, size: const Size(400, 1200));
      await tester.enterText(find.byKey(const Key('manual.protein')), '1.2.');
      await tester.pump();
      expectUnder(tester, 'manual.protein', 'Enter a number');
      expect(find.text('Must be 0–500 g'), findsNothing);
    });

    testWidgets('a name with no protein, carbs or fat says why Log is off', (tester) async {
      await _pump(tester, size: const Size(400, 1200));
      expect(find.text('Add some protein, carbs or fat'), findsNothing, reason: 'nothing typed yet');
      await tester.enterText(find.byKey(const Key('manual.name')), 'Water');
      await tester.pump();
      expect(find.text('Add some protein, carbs or fat'), findsOneWidget);
      expect(tester.widget<FsButton>(find.byKey(const Key('manual.log'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('manual.carbs')), '1');
      await tester.pump();
      expect(find.text('Add some protein, carbs or fat'), findsNothing);
    });
  });

  testWidgets('a failed save offers Try again, which sends the typed food again (NU-4)', (tester) async {
    final repo = await _pump(tester, size: const Size(400, 1200));
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.pump();
    repo.failNext = true;
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save Turon."), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'log 2026-10-14 snack Turon x1.0'), hasLength(2));
    expect(repo.days['2026-10-14']!.entries.map((e) => e.name), contains('Turon'));
  });
}
