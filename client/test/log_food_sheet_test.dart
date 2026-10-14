import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_food_sheet.dart';

const _rice = Food(source: 'local', id: 3, name: 'Steamed white rice', servingDesc: '1 cup', kcal: 205, proteinG: 4.3, carbsG: 44.5, fatG: 0.4);
const _shake = Food(source: 'fatsecret', externalId: 'fs-1', name: 'Mango Shake', servingDesc: '1 glass', kcal: 250, proteinG: 4, carbsG: 50, fatG: 3.5);

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
}
