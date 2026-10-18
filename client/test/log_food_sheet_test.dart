import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_food_sheet.dart';

const _rice = Food(source: 'local', id: 3, name: 'Steamed white rice', servingDesc: '1 cup', kcal: 205, proteinG: 4.3, carbsG: 44.5, fatG: 0.4);
const _shake = Food(source: 'fatsecret', externalId: 'fs-1', name: 'Mango Shake', servingDesc: '1 glass', kcal: 250, proteinG: 4, carbsG: 50, fatG: 3.5);
const _oatmeal = Food(source: 'local', id: 9, name: 'Oatmeal', servingDesc: '1 bowl', kcal: 150, proteinG: 5, carbsG: 27, fatG: 3, fiberG: 3);
const _juice = Food(source: 'local', id: 11, name: 'Mango juice', servingDesc: '1 glass', kcal: 120, proteinG: 1, carbsG: 28, fatG: 0, sugarG: 9.7, sodiumMg: 124);

Future<LogChoice?> _open(WidgetTester tester, Food food) async {
  LogChoice? result;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () async => result = await showLogFoodSheet(context, food, mealType: 'lunch'),
      child: const Text('open'),
    ),
  ))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// Opens the sheet and returns a getter for its result (null until it closes).
Future<LogChoice? Function()> _openForResult(WidgetTester tester, Food food) async {
  LogChoice? result;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () async => result = await showLogFoodSheet(context, food, mealType: 'lunch'),
      child: const Text('open'),
    ),
  ))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

/// Opens the sheet to change a logged food: [food] per serving, in
/// [mealType], at [servings]. Returns a getter for its result, and whether
/// it has closed.
Future<({LogChoice? Function() result, bool Function() closed})> _openToChange(
    WidgetTester tester, Food food, {String mealType = 'dinner', double servings = 1.5}) async {
  LogChoice? result;
  var closed = false;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () async {
        result = await showLogFoodSheet(context, food, mealType: mealType, servings: servings, changing: true);
        closed = true;
      },
      child: const Text('open'),
    ),
  ))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (result: () => result, closed: () => closed);
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('logSheet.log')));
  await tester.pumpAndSettle();
}

Future<void> _editNumbers(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('logSheet.edit')));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField))).controller!.text;

void main() {
  testWidgets('servings step by a half and the numbers follow', (tester) async {
    await _open(tester, _rice);
    expect(find.text('205 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('servings.plus')));
    await tester.pump();
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('308 kcal'), findsOneWidget); // 307.5 -> 308
    await tester.tap(find.byKey(const Key('servings.minus')));
    await tester.tap(find.byKey(const Key('servings.minus')));
    await tester.pump();
    expect(find.text('0.5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('servings.minus')));
    await tester.pump();
    expect(find.text('0.5'), findsOneWidget, reason: 'never below half a serving');
  });

  testWidgets('Log returns the meal and servings chosen', (tester) async {
    LogChoice? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () async => result = await showLogFoodSheet(context, _rice, mealType: 'lunch'),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dinner'));
    await tester.tap(find.byKey(const Key('servings.plus')));
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result!.mealType, 'dinner');
    expect(result!.servings, 1.5);
  });

  testWidgets('a FatSecret food carries the attribution', (tester) async {
    await _open(tester, _shake);
    expect(find.text('Powered by fatsecret Platform API'), findsOneWidget);
  });

  testWidgets('a FitSync food does not', (tester) async {
    await _open(tester, _rice);
    expect(find.text('Powered by fatsecret Platform API'), findsNothing);
  });

  testWidgets('the sheet says which serving the numbers are for, without naming a source', (tester) async {
    await _open(tester, _rice);
    expect(find.text('Per 1 cup'), findsOneWidget);
    expect(find.textContaining('FitSync food list'), findsNothing);
  });

  testWidgets('a FatSecret food shows its serving but no source label', (tester) async {
    await _open(tester, _shake);
    expect(find.text('Per 1 glass'), findsOneWidget);
    expect(find.text('FatSecret'), findsNothing);
  });

  testWidgets('your own entry is marked as yours', (tester) async {
    await _open(tester, const Food(source: 'manual', name: 'Turon', servingDesc: '1 piece', kcal: 198, proteinG: 2, carbsG: 34, fatG: 6));
    expect(find.text('Per 1 piece · your entry'), findsOneWidget);
  });

  testWidgets('Edit numbers shows labelled boxes filled with the food\'s numbers', (tester) async {
    await _open(tester, _rice);
    expect(find.byKey(const Key('logSheet.protein')), findsNothing, reason: 'hidden until asked for');
    await _editNumbers(tester);
    expect(find.text('Protein (g)'), findsOneWidget);
    expect(find.text('Carbs (g)'), findsOneWidget);
    expect(find.text('Fat (g)'), findsOneWidget);
    expect(find.text('Fiber (g)'), findsOneWidget);
    expect(_fieldText(tester, 'logSheet.protein'), '4.3');
    expect(_fieldText(tester, 'logSheet.carbs'), '44.5');
    expect(_fieldText(tester, 'logSheet.fat'), '0.4');
    expect(_fieldText(tester, 'logSheet.fiber'), '', reason: 'unknown fiber starts blank, not 0');
  });

  testWidgets('Edit numbers prefills fiber when the food lists it', (tester) async {
    await _open(tester, _oatmeal);
    await _editNumbers(tester);
    expect(_fieldText(tester, 'logSheet.fiber'), '3');
  });

  testWidgets('the numbers line shows fiber when the food lists it', (tester) async {
    await _open(tester, _oatmeal);
    expect(find.textContaining('Fiber 3 g'), findsOneWidget);
  });

  testWidgets('the numbers line omits fiber when the food has none, with no "not listed" text', (tester) async {
    await _open(tester, _rice);
    expect(find.textContaining('Fiber'), findsNothing);
    expect(find.textContaining('not listed'), findsNothing);
  });

  testWidgets('the extras line shows sugar and sodium when both are known', (tester) async {
    await _open(tester, _juice);
    expect(find.byKey(const Key('logSheet.extras')), findsOneWidget);
    expect(find.text('Sugar 9.7 g · Sodium 124 mg'), findsOneWidget);
  });

  testWidgets('the extras line is readable, not a dim caption: it carries data', (tester) async {
    await _open(tester, _juice);
    final style = tester.widget<Text>(find.byKey(const Key('logSheet.extras'))).style!;
    expect(style.color, FsTokens.light.text2, reason: 'text3 falls below WCAG AA for this line');
  });

  testWidgets('the extras line shows only the known part when one is unknown', (tester) async {
    await _open(tester, const Food(
      source: 'local', id: 12, name: 'Banana', servingDesc: '1 pc', kcal: 105, proteinG: 1.3, carbsG: 27, fatG: 0.4, sugarG: 9.7,
    ));
    expect(find.text('Sugar 9.7 g'), findsOneWidget);
    expect(find.textContaining('Sodium'), findsNothing);
  });

  testWidgets('there is no extras line when neither sugar nor sodium is known', (tester) async {
    await _open(tester, _rice);
    expect(find.byKey(const Key('logSheet.extras')), findsNothing);
  });

  testWidgets('sodium on the extras line scales with servings and groups thousands', (tester) async {
    await _open(tester, const Food(
      source: 'local', id: 13, name: 'Instant noodles', servingDesc: '1 pack', kcal: 380, proteinG: 8, carbsG: 51, fatG: 15, sodiumMg: 925,
    ));
    await tester.tap(find.byKey(const Key('servings.plus')));
    await tester.tap(find.byKey(const Key('servings.plus')));
    await tester.pump();
    expect(find.text('Sodium 1,850 mg'), findsOneWidget);
  });

  testWidgets('Edit numbers shows sugar and sodium boxes prefilled when the food lists them', (tester) async {
    await _open(tester, _juice);
    await _editNumbers(tester);
    expect(find.text('Sugar (g)'), findsOneWidget);
    expect(find.text('Sodium (mg)'), findsOneWidget);
    expect(_fieldText(tester, 'logSheet.sugar'), '9.7');
    expect(_fieldText(tester, 'logSheet.sodium'), '124');
  });

  testWidgets('Edit numbers leaves sugar and sodium blank when the food lists neither', (tester) async {
    await _open(tester, _rice);
    await _editNumbers(tester);
    expect(_fieldText(tester, 'logSheet.sugar'), '');
    expect(_fieldText(tester, 'logSheet.sodium'), '');
  });

  testWidgets('changing only sugar logs a manual entry with the new sugar and kcal worked out from protein, carbs and fat', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.sugar')), matching: find.byType(TextField)), '12');
    await tester.pump();
    // 4*4.3 + 4*44.5 + 9*0.4 = 198.8 -> 199, same as any other manual entry; sugar never adds calories.
    expect(find.text('199 kcal'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    final edited = result()!.edited!;
    expect(edited.sugarG, 12);
    expect(edited.kcal, 199);
  });

  testWidgets('clearing sodium logs it as unknown', (tester) async {
    final result = await _openForResult(tester, _juice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.sodium')), matching: find.byType(TextField)), '');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result()!.edited!.sodiumMg, isNull);
  });

  testWidgets('an out-of-range sodium says so and Log stays off', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.sodium')), matching: find.byType(TextField)), '20001');
    await tester.pump();
    expect(find.text('Sodium must be 0–20,000 mg'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNull, reason: 'the sheet stays open');
  });

  testWidgets('an out-of-range sugar says so and Log stays off', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.sugar')), matching: find.byType(TextField)), '600');
    await tester.pump();
    expect(find.text('Each value must be 0–500 g'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNull, reason: 'the sheet stays open');
  });

  testWidgets('edited numbers are logged as your own entry, times the servings', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.protein')), matching: find.byType(TextField)), '10');
    await tester.pump();
    // 4*10 + 4*44.5 + 9*0.4 = 221.6 -> 222 per serving.
    expect(find.text('222 kcal'), findsOneWidget);
    expect(find.text('Calories worked out from protein, carbs and fat.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('servings.plus')));
    await tester.pump();
    expect(find.text('333 kcal'), findsOneWidget); // 221.6 x 1.5 = 332.4 -> per-serving 222 x 1.5 = 333
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    final choice = result()!;
    expect(choice.servings, 1.5);
    final edited = choice.edited!;
    expect(edited.source, 'manual');
    expect(edited.name, 'Steamed white rice');
    expect(edited.servingDesc, '1 cup');
    expect(edited.proteinG, 10);
    expect(edited.carbsG, 44.5);
    expect(edited.fatG, 0.4);
    expect(edited.kcal, 222);
  });

  testWidgets('changing only fiber logs a manual entry whose kcal is worked out from protein, carbs and fat', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fiber')), matching: find.byType(TextField)), '5');
    await tester.pump();
    // The server works out every manual entry's kcal as 4·4·9, so the preview
    // must too: 4*4.3 + 4*44.5 + 9*0.4 = 198.8 -> 199, not the listed 205.
    expect(find.text('199 kcal'), findsOneWidget);
    expect(find.text('Calories worked out from protein, carbs and fat.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    final edited = result()!.edited!;
    expect(edited.source, 'manual');
    expect(edited.proteinG, _rice.proteinG);
    expect(edited.carbsG, _rice.carbsG);
    expect(edited.fatG, _rice.fatG);
    expect(edited.fiberG, 5);
    expect(edited.kcal, 199, reason: 'what the server will compute');
  });

  testWidgets('the edited kcal matches the server, which rounds each gram to 2 decimals first', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fat')), matching: find.byType(TextField)), '0.1449');
    await tester.pump();
    // Server: 0.1449 -> 0.14 g; 4*4.3 + 4*44.5 + 9*0.14 = 196.46 -> 196 (unrounded: 196.50 -> 197).
    expect(find.text('196 kcal'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result()!.edited!.kcal, 196);
  });

  testWidgets('an edited food with a long name and serving fits what the server accepts', (tester) async {
    final longName = 'Rice ' * 24; // 120 characters
    final longServing = '1 large bowl, ' * 5; // 70 characters
    final result = await _openForResult(tester, Food(
      source: 'fatsecret', externalId: 'fs-long', name: longName, servingDesc: longServing,
      kcal: 205, proteinG: 4.3, carbsG: 44.5, fatG: 0.4,
    ));
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.protein')), matching: find.byType(TextField)), '10');
    await tester.pump();
    // The long name wraps, so Log sits below the fold.
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    final edited = result()!.edited!;
    expect(edited.name.length, lessThanOrEqualTo(100));
    expect(edited.servingDesc!.length, lessThanOrEqualTo(60));
    // Cut at 100, then the trailing space trimmed.
    expect(edited.name, ('Rice ' * 20).trimRight());
    expect(edited.servingDesc, longServing.substring(0, 60));
  });

  testWidgets('clipping counts what the server counts and never splits a character', (tester) async {
    // Each 🍚 is one character but two UTF-16 units, which is what the
    // server's length check counts.
    final result = await _openForResult(tester, Food(
      source: 'fatsecret', externalId: 'fs-emoji', name: '🍚' * 60, servingDesc: '🍚' * 35,
      kcal: 205, proteinG: 4.3, carbsG: 44.5, fatG: 0.4,
    ));
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.protein')), matching: find.byType(TextField)), '10');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    final edited = result()!.edited!;
    expect(edited.name, '🍚' * 50);
    expect(edited.servingDesc, '🍚' * 30);
  });

  testWidgets('clearing fiber logs it as unknown', (tester) async {
    final result = await _openForResult(tester, _oatmeal);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fiber')), matching: find.byType(TextField)), '');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result()!.edited!.fiberG, isNull);
  });

  testWidgets('opening Edit numbers without changing anything logs the original food', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result()!.edited, isNull);
  });

  testWidgets('a food with no protein, carbs or fat can still be logged with the boxes open', (tester) async {
    final result = await _openForResult(tester, const Food(
      source: 'local', id: 40, name: 'Diet soda', servingDesc: '1 can', kcal: 0, proteinG: 0, carbsG: 0, fatG: 0,
    ));
    await _editNumbers(tester);
    expect(find.text('Add some protein, carbs or fat'), findsNothing, reason: 'nothing was changed');
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNotNull);
    expect(result()!.edited, isNull, reason: 'logged as listed');
  });

  testWidgets('a listed value over 500 g the user did not change does not block Log', (tester) async {
    final result = await _openForResult(tester, const Food(
      source: 'fatsecret', externalId: 'fs-cake', name: 'Whole cake', servingDesc: '1 cake',
      kcal: 4990, proteinG: 60, carbsG: 520, fatG: 290,
    ));
    await _editNumbers(tester);
    expect(find.text('Each value must be 0–500 g'), findsNothing, reason: 'nothing was changed');
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNotNull);
    expect(result()!.edited, isNull, reason: 'logged as listed');
  });

  testWidgets('changing every macro to 0 says why and Log stays off', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    for (final key in ['logSheet.protein', 'logSheet.carbs', 'logSheet.fat']) {
      await tester.enterText(find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)), '0');
    }
    await tester.pump();
    expect(find.text('Add some protein, carbs or fat'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNull, reason: 'the sheet stays open');
  });

  testWidgets('an out-of-range number says so and Log stays off', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fat')), matching: find.byType(TextField)), '600');
    await tester.pump();
    expect(find.text('Each value must be 0–500 g'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNull, reason: 'the sheet stays open');
  });

  testWidgets('an out-of-range fiber says so and Log stays off', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fiber')), matching: find.byType(TextField)), '600');
    await tester.pump();
    expect(find.text('Each value must be 0–500 g'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNull, reason: 'the sheet stays open');
  });

  testWidgets('a lone dot in protein is unreadable, not a change, and does not crash', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.protein')), matching: find.byType(TextField)), '.');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Each value must be 0–500 g'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result(), isNull, reason: 'the sheet stays open');
  });

  testWidgets('the boxes fit a 320 dp phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showLogFoodSheet(context, _rice, mealType: 'lunch'),
          child: const Text('open'),
        ),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _editNumbers(tester);
    expect(tester.takeException(), isNull);
  });

  group('changing a logged food', () {
    testWidgets("opens on the entry's meal and servings, with Save changes in place of Log", (tester) async {
      await _openToChange(tester, _rice, mealType: 'dinner', servings: 1.5);
      expect(find.text('1.5'), findsOneWidget);
      expect(find.text('308 kcal'), findsOneWidget); // 205 x 1.5
      final meals = tester.widget<FsSegmented>(find.byType(FsSegmented));
      expect(meals.selected, 'dinner');
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Log'), findsNothing);
    });

    testWidgets('saving with nothing changed closes the sheet and returns nothing', (tester) async {
      final sheet = await _openToChange(tester, _rice);
      await _editNumbers(tester); // opened but left as they were
      await _save(tester);
      expect(sheet.closed(), isTrue);
      expect(sheet.result(), isNull);
      expect(find.text('Save changes'), findsNothing);
    });

    testWidgets('a new meal comes back in the choice, with the numbers left as they were', (tester) async {
      final sheet = await _openToChange(tester, _rice, mealType: 'dinner', servings: 1.5);
      await tester.tap(find.text('Snack'));
      await tester.pump();
      await _save(tester);
      final choice = sheet.result()!;
      expect(choice.mealType, 'snack');
      expect(choice.servings, 1.5);
      expect(choice.edited, isNull);
    });

    testWidgets('new servings come back in the choice', (tester) async {
      final sheet = await _openToChange(tester, _rice, mealType: 'dinner', servings: 1.5);
      await tester.tap(find.byKey(const Key('servings.plus')));
      await tester.pump();
      await _save(tester);
      final choice = sheet.result()!;
      expect(choice.mealType, 'dinner');
      expect(choice.servings, 2);
      expect(choice.edited, isNull);
    });

    testWidgets("new numbers come back as the user's own food, per serving", (tester) async {
      final sheet = await _openToChange(tester, _rice);
      await _editNumbers(tester);
      await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.protein')), matching: find.byType(TextField)), '10');
      await tester.pump();
      await _save(tester);
      final edited = sheet.result()!.edited!;
      expect(edited.source, 'manual');
      expect(edited.name, 'Steamed white rice');
      expect(edited.proteinG, 10);
      expect(edited.kcal, 222);
    });

    testWidgets('logging still reads Log', (tester) async {
      await _open(tester, _rice);
      expect(find.text('Log'), findsOneWidget);
      expect(find.text('Save changes'), findsNothing);
    });
  });
}
