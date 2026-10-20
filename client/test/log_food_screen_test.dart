import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/add_food_manually_screen.dart';
import 'package:fitsync/features/nutrition/presentation/log_food_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

class _SearchRepo extends FakeNutritionRepository {
  final List<String> queries = [];
  bool unavailable = false;

  @override
  Future<FoodSearchResult> search(String q) async {
    queries.add(q);
    return FoodSearchResult(fatsecretUnavailable: unavailable, foods: [
      const Food(source: 'local', id: 6, name: 'Chicken adobo', servingDesc: '1 serving', kcal: 320, proteinG: 28, carbsG: 4, fatG: 21),
      if (!unavailable)
        const Food(source: 'fatsecret', externalId: 'fs-2', name: 'Adobo Flakes', servingDesc: '1 cup', kcal: 410, proteinG: 30, carbsG: 2, fatG: 31),
    ]);
  }

  @override
  Future<List<Food>> recent() async =>
      const [Food(source: 'manual', name: 'Turon', kcal: 198, proteinG: 2, carbsG: 34, fatG: 6)];
}

/// A FatSecret detail that loads only when the test says so.
class _GatedRepo extends _SearchRepo {
  final gate = Completer<Food>();

  @override
  Future<Food> fatsecretFood(String externalId) => gate.future;
}

Future<void> _pump(WidgetTester tester, _SearchRepo repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
    ],
    child: MaterialApp(home: Consumer(builder: (context, ref, _) {
      ref.watch(nutritionDayProvider); // loaded, as on the Nutrition tab
      return Scaffold(body: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const LogFoodScreen(mealType: 'lunch'),
        )),
        child: const Text('go'),
      ));
    })),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('waits for typing to pause, then shows results with labels', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    expect(find.text('Log food'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('food.search')), 'ad');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.queries, ['adobo']);
    expect(find.text('Chicken adobo'), findsOneWidget);
    expect(find.text('Adobo Flakes'), findsOneWidget);
    expect(find.text('FatSecret'), findsNothing, reason: 'no source tag on rows');
    expect(find.text('Powered by fatsecret Platform API'), findsOneWidget);
  });

  testWidgets('the search stops at 60 characters, the most the server accepts', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'a' * 70);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.queries, ['a' * 60]);
  });

  // The phone reached the server, so its connection is fine: the note says
  // the gap is temporary and what to do, without blaming the connection.
  testWidgets('FatSecret down shows a quiet note', (tester) async {
    final repo = _SearchRepo()..unavailable = true;
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text("Some foods couldn't load right now. Try again later."), findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
    expect(find.text('Powered by fatsecret Platform API'), findsNothing);
  });

  testWidgets('Recents lists recent foods', (tester) async {
    await _pump(tester, _SearchRepo());
    await tester.tap(find.text('Recents'));
    await tester.pumpAndSettle();
    expect(find.text('Turon'), findsOneWidget);
  });

  // The meal is shown, and can be changed, before anything is searched --
  // it used to be fixed in the title and changeable only in the last step.
  testWidgets('the meal it opened for is shown at the top, before searching', (tester) async {
    await _pump(tester, _SearchRepo());
    final picker = find.byKey(const Key('log.meal'));
    expect(find.descendant(of: picker, matching: find.text('Lunch')), findsOneWidget);
    expect(tester.getSize(picker).height, greaterThanOrEqualTo(48));
  });

  // Two identical pill rows -- the meal and the All / Recents filter -- read
  // as one kind of thing; the meal is a labelled one-line choice instead.
  testWidgets('the meal choice is labelled as where the food goes', (tester) async {
    await _pump(tester, _SearchRepo());
    final label = tester.getRect(find.text('ADDING TO'));
    final picker = tester.getRect(find.byKey(const Key('log.meal')));
    expect(label.right, lessThanOrEqualTo(picker.left), reason: 'the label leads the choice');
    expect(label.center.dy, closeTo(picker.center.dy, 4), reason: 'on one line');
  });

  testWidgets('a screen reader can hear and press the meal choice', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _SearchRepo());
    final node = tester.getSemantics(find.byKey(const Key('log.meal')));
    // Heard as one thing: what it is for, the meal, and that it is a button.
    expect(node.label, contains('ADDING TO'));
    expect(node.label, contains('Lunch'));
    expect(node.tooltip, 'Change meal');
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  // Ink paints on the nearest Material behind it: on the screen's, it drew
  // a square halo behind the pill and hid the focus colour. Pressed, the
  // highlight is painted on the pill, clipped to its rounded edge: the middle
  // is covered and the box's corners are not.
  testWidgets("the meal choice's press fills the pill, inside its rounded edge", (tester) async {
    await _pump(tester, _SearchRepo());
    final ink = find.descendant(of: find.byKey(const Key('log.meal')), matching: find.byType(InkWell));
    final pill = tester.getRect(ink);
    final gesture = await tester.startGesture(pill.center);
    await tester.pump(const Duration(milliseconds: 200));
    final controller = Material.of(tester.element(ink)) as RenderBox;
    expect(controller.size, pill.size, reason: "the pill's own Material");
    final local = pill.size.center(Offset.zero);
    expect(
      controller,
      paints
        ..clipPath(
          pathMatcher: isPathThat(
            includes: [local],
            excludes: [const Offset(1, 1), Offset(pill.width - 1, pill.height - 1)],
          ),
        ),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  // The 48 dp row is the target, not just the drawn pill: a tap above or
  // below the pill's rounded ends, inside the row, opens the meals too.
  testWidgets('a tap in the row by either end of the pill opens the meals', (tester) async {
    await _pump(tester, _SearchRepo());
    final row = tester.getRect(find.byKey(const Key('log.meal')));
    final pill = tester.getRect(find.descendant(of: find.byKey(const Key('log.meal')), matching: find.byType(InkWell)));
    for (final point in [Offset(pill.left + 2, row.top + 0.5), Offset(pill.right - 2, row.bottom - 0.5)]) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('log.meal.dinner')), findsOneWidget, reason: 'tap at $point');
      await tester.tapAt(const Offset(5, 5)); // outside the menu: closes it
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('log.meal.dinner')), findsNothing, reason: 'the menu closed');
    }
  });

  Future<void> pickMeal(WidgetTester tester, String meal) async {
    await tester.tap(find.byKey(const Key('log.meal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('log.meal.$meal')));
    await tester.pumpAndSettle();
  }

  testWidgets('a meal picked at the top is where the food goes', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await pickMeal(tester, 'dinner');
    expect(
      find.descendant(of: find.byKey(const Key('log.meal')), matching: find.text('Dinner')),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('log 2026-10-14 dinner Chicken adobo x1.0'));
  });

  testWidgets('Add manually starts from the meal picked at the top', (tester) async {
    await _pump(tester, _SearchRepo());
    await pickMeal(tester, 'snack');
    await tester.tap(find.byKey(const Key('food.manual')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AddFoodManuallyScreen>(find.byType(AddFoodManuallyScreen)).mealType,
      'snack',
    );
  });

  testWidgets('choosing a food logs it and returns to Nutrition', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget, reason: 'back on the screen underneath');
    expect(repo.calls, contains('log 2026-10-14 lunch Chicken adobo x1.0'));
  });

  testWidgets('a failed save says so after returning', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    repo.failNext = true;
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save — try again."), findsOneWidget);
  });

  testWidgets('a food with edited numbers is saved as your own entry', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.protein')), matching: find.byType(TextField)), '30');
    await tester.pump();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.source, 'manual');
    expect(repo.lastLogged!.name, 'Chicken adobo');
    expect(repo.lastLogged!.proteinG, 30);
  });

  testWidgets('before typing, it asks what you ate and offers foods to tap', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    expect(find.text('What did you eat?'), findsOneWidget);
    expect(find.text('Search by name, like adobo or rice'), findsOneWidget);
    for (final food in ['Rice', 'Chicken adobo', 'Egg', 'Tapsilog', 'Banana']) {
      // The design system's chip, so it follows the theme.
      expect(find.widgetWithText(FsChip, food), findsOneWidget);
    }
    expect(find.textContaining('at least 2 letters'), findsNothing);
    expect(find.textContaining('FatSecret'), findsNothing);
  });

  testWidgets('the suggested foods fit a 320 dp phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [nutritionRepositoryProvider.overrideWithValue(_SearchRepo())],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: const LogFoodScreen(mealType: 'lunch'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(FsChip), findsNWidgets(5));
  });

  testWidgets('tapping a suggested food searches for it', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    expect(repo.queries, ['Chicken adobo']);
    expect(find.text('Adobo Flakes'), findsOneWidget);
  });

  testWidgets('a suggested food answers a tap 7 dp below the last row', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    final chips = find.byType(FsChip);
    final last = tester.getRect(chips.last);
    await tester.tapAt(last.bottomCenter + const Offset(0, 7));
    await tester.pumpAndSettle();
    expect(repo.queries, hasLength(1));
  });

  testWidgets('a suggested food answers a tap 7 dp above the first row', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    final first = tester.getRect(find.widgetWithText(FsChip, 'Rice'));
    await tester.tapAt(first.topCenter - const Offset(0, 7));
    await tester.pumpAndSettle();
    expect(repo.queries, ['Rice']);
  });

  testWidgets('one letter just waits, with nothing to read', (tester) async {
    await _pump(tester, _SearchRepo());
    await tester.enterText(find.byKey(const Key('food.search')), 'a');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('What did you eat?'), findsNothing);
    expect(find.textContaining('at least 2 letters'), findsNothing);
  });

  Future<void> searchAdobo(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('a FatSecret food opens with its real serving, and that is what gets logged', (tester) async {
    final repo = _SearchRepo()
      ..fatsecretDetails['fs-2'] = const Food(source: 'fatsecret', externalId: 'fs-2', name: 'Adobo Flakes',
          servingDesc: '1 bowl', kcal: 300, proteinG: 22, carbsG: 2, fatG: 22);
    await _pump(tester, repo);
    await searchAdobo(tester);
    await tester.tap(find.text('Adobo Flakes'));
    await tester.pumpAndSettle();
    expect(repo.fatsecretCalls, ['fs-2']);
    expect(find.text('Per 1 bowl'), findsOneWidget);
    expect(find.text('300 kcal'), findsOneWidget, reason: 'not the list\'s 410');
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.kcal, 300);
    expect(repo.lastLogged!.servingDesc, '1 bowl');
  });

  testWidgets('if a FatSecret food can\'t be loaded, it says so and opens nothing', (tester) async {
    final repo = _SearchRepo()..failFatsecret = true;
    await _pump(tester, repo);
    await searchAdobo(tester);
    await tester.tap(find.text('Adobo Flakes'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load this food. Try again."), findsOneWidget);
    expect(find.byKey(const Key('logSheet.log')), findsNothing);
  });

  testWidgets('loading a FatSecret food shows a bar without moving the list', (tester) async {
    final repo = _GatedRepo();
    await _pump(tester, repo);
    await searchAdobo(tester);
    final before = tester.getTopLeft(find.text('Chicken adobo'));
    await tester.tap(find.text('Adobo Flakes'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.getTopLeft(find.text('Chicken adobo')), before, reason: 'the bar has its own space');
    repo.gate.complete(const Food(source: 'fatsecret', externalId: 'fs-2', name: 'Adobo Flakes',
        servingDesc: '1 bowl', kcal: 300, proteinG: 22, carbsG: 2, fatG: 22));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Per 1 bowl'), findsOneWidget);
  });

  testWidgets('a FitSync food opens straight away, with no lookup', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await searchAdobo(tester);
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    expect(repo.fatsecretCalls, isEmpty);
    expect(find.byKey(const Key('logSheet.log')), findsOneWidget);
  });
}
