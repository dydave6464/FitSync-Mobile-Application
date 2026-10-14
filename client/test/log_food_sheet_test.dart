import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_food_sheet.dart';

const _rice = Food(source: 'local', id: 3, name: 'Steamed white rice', servingDesc: '1 cup', kcal: 205, proteinG: 4.3, carbsG: 44.5, fatG: 0.4);
const _shake = Food(source: 'fatsecret', externalId: 'fs-1', name: 'Mango Shake', servingDesc: '1 glass', kcal: 250, proteinG: 4, carbsG: 50, fatG: 3.5);
const _oatmeal = Food(source: 'local', id: 9, name: 'Oatmeal', servingDesc: '1 bowl', kcal: 150, proteinG: 5, carbsG: 27, fatG: 3, fiberG: 3);

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

  testWidgets('the numbers line says fiber is not listed when the food has none', (tester) async {
    await _open(tester, _rice);
    expect(find.textContaining('Fiber not listed'), findsOneWidget);
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

  testWidgets('changing only fiber logs a manual entry with the new fiberG and an unchanged kcal', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fiber')), matching: find.byType(TextField)), '5');
    await tester.pump();
    expect(find.text('205 kcal'), findsOneWidget, reason: 'fiber never changes kcal');
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    final edited = result()!.edited!;
    expect(edited.source, 'manual');
    expect(edited.proteinG, _rice.proteinG);
    expect(edited.carbsG, _rice.carbsG);
    expect(edited.fatG, _rice.fatG);
    expect(edited.fiberG, 5);
    expect(edited.kcal, _rice.kcal);
  });

  testWidgets('clearing fiber logs it as unknown', (tester) async {
    final result = await _openForResult(tester, _oatmeal);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fiber')), matching: find.byType(TextField)), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result()!.edited!.fiberG, isNull);
  });

  testWidgets('opening Edit numbers without changing anything logs the original food', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(result()!.edited, isNull);
  });

  testWidgets('an out-of-range number says so and Log stays off', (tester) async {
    final result = await _openForResult(tester, _rice);
    await _editNumbers(tester);
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.fat')), matching: find.byType(TextField)), '600');
    await tester.pump();
    expect(find.text('Each value must be 0–500 g'), findsOneWidget);
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
}
