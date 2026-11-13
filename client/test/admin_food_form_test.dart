import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/content_screen.dart';
import 'package:fitsync/features/admin/presentation/food_form_screen.dart';
import 'package:fitsync/features/admin/presentation/meals_tab.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';

import 'helpers/fake_admin_repository.dart';

/// The form pushed over a page that keeps the Meals list alive, so a test
/// can see the list asked again and the SnackBar left behind on save.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  AdminFood? food,
  bool dark = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.listen(adminFoodsProvider, (_, _) {});
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FoodFormScreen(food: food),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

Finder _field(String name) => find.byKey(Key('admin.food.$name'));

Future<void> _type(WidgetTester tester, String name, String text) async {
  await tester.ensureVisible(_field(name));
  await tester.enterText(_field(name), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Everything the form needs, calories left to be worked out.
Future<void> _fillRequired(WidgetTester tester) async {
  await _type(tester, 'name', 'Chicken adobo');
  await _tap(tester, find.text('Filipino'));
  await _tap(tester, find.byKey(const Key('admin.food.type.home')));
  await _type(tester, 'serving', '1 cup');
  await _type(tester, 'protein', '28');
  await _type(tester, 'carbs', '4');
  await _type(tester, 'fat', '21');
}

VoidCallback? _save(WidgetTester tester) =>
    tester.widget<FsButton>(find.byKey(const Key('save'))).onPressed;

Future<void> _pressSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the add form names every field', (tester) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('Add food'), findsOneWidget);
    // The text fields' labels, drawn as eyebrows.
    for (final label in ['Name', 'Serving']) {
      expect(
        find.byWidgetPredicate((w) => w is FsField && w.label == label),
        findsOneWidget,
        reason: label,
      );
    }
    for (final label in [
      'Calories (kcal) · optional',
      'Protein (g)',
      'Carbs (g)',
      'Fat (g)',
      'Fiber (g) · optional',
      'Sugar (g) · optional',
      'Sodium (mg) · optional',
    ]) {
      await tester.ensureVisible(find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Filipino'), findsOneWidget);
    expect(find.text('International'), findsOneWidget);
    for (final type in [
      'Home-cooked',
      'Fruit & veg',
      'Bread & kakanin',
      'Canned & instant',
      'Drink',
      'Street food',
      'Snack & sweet',
      'Fast food',
      'Condiment',
    ]) {
      expect(find.text(type), findsOneWidget, reason: type);
    }
    expect(
      find.text('Leave empty to work it out from protein, carbs and fat.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.food.hide')), findsNothing);
    expect(find.byKey(const Key('admin.food.show')), findsNothing);
  });

  testWidgets('number fields open a number keyboard', (tester) async {
    await _pump(tester, FakeAdminRepository());

    for (final name in ['protein', 'carbs', 'fat', 'fiber', 'sugar']) {
      final field = tester.widget<TextField>(_field(name));
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
        reason: name,
      );
    }
    final kcal = tester.widget<TextField>(_field('kcal'));
    expect(kcal.keyboardType, const TextInputType.numberWithOptions());
  });

  testWidgets('Save waits for every required field', (tester) async {
    await _pump(tester, FakeAdminRepository());
    expect(_save(tester), isNull);
    expect(find.text('Add a name'), findsOneWidget);

    await _type(tester, 'name', 'Chicken adobo');
    expect(find.text('Choose Filipino or International'), findsOneWidget);
    await _tap(tester, find.text('Filipino'));
    expect(find.text('Choose a type'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('admin.food.type.home')));
    expect(find.text('Add a serving'), findsOneWidget);
    await _type(tester, 'serving', '1 cup');
    expect(find.text('Add protein, carbs and fat'), findsOneWidget);
    await _type(tester, 'protein', '28');
    await _type(tester, 'carbs', '4');
    expect(_save(tester), isNull);
    await _type(tester, 'fat', '21');

    expect(_save(tester), isNotNull);
  });

  testWidgets('a food with nothing to count is not saved', (tester) async {
    await _pump(tester, FakeAdminRepository());
    await _fillRequired(tester);

    await _type(tester, 'protein', '0');
    await _type(tester, 'carbs', '0');
    await _type(tester, 'fat', '0');
    expect(_save(tester), isNull);
    expect(find.text('Add calories, protein, carbs or fat'), findsOneWidget);

    // A drink label may give only calories.
    await _type(tester, 'kcal', '120');
    expect(_save(tester), isNotNull);
  });

  testWidgets('an out-of-range number is named under its field', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository());
    await _fillRequired(tester);

    await _type(tester, 'protein', '600');

    expect(find.text('Must be 0–500 g'), findsOneWidget);
    expect(_save(tester), isNull);
  });

  testWidgets('Save adds the food, leaving empty calories to the server', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo);
    final listCalls = repo.foodsCalls.length;
    await _fillRequired(tester);
    await _type(tester, 'sodium', '870.5');

    await _pressSave(tester);

    final sent = repo.createFoodCalls.single;
    expect(sent.toJson(), {
      'name': 'Chicken adobo',
      'category': 'filipino',
      'foodType': 'home',
      'servingDesc': '1 cup',
      'kcal': null,
      'proteinG': 28.0,
      'carbsG': 4.0,
      'fatG': 21.0,
      'fiberG': null,
      'sugarG': null,
      'sodiumMg': 870.5,
      'suggestMeals': <String>[],
      'suggestWithRice': false,
      'contains': <String>[],
    });
    expect(find.byType(FoodFormScreen), findsNothing);
    expect(find.text('Food added.'), findsOneWidget);
    expect(repo.foodsCalls.length, greaterThan(listCalls));
  });

  testWidgets("typed calories are the label's and are sent", (tester) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo);
    await _fillRequired(tester);
    await _tap(tester, find.text('International'));
    await _type(tester, 'kcal', '350');

    await _pressSave(tester);

    expect(repo.createFoodCalls.single.kcal, 350);
    expect(repo.createFoodCalls.single.category, 'international');
  });

  testWidgets("the server's field error shows under that field", (
    tester,
  ) async {
    var fail = true;
    final repo = FakeAdminRepository(
      createFood: (_) async {
        if (fail) {
          throw const ApiException(
            'INVALID_NUTRITION_FIELD',
            'proteinG must be 0 to 500.',
            details: [
              {'field': 'proteinG'},
            ],
          );
        }
        return sampleFood();
      },
    );
    await _pump(tester, repo);
    await _fillRequired(tester);

    await _pressSave(tester);

    expect(find.byType(FoodFormScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.food.protein.box')),
        matching: find.text('proteinG must be 0 to 500.'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('error')), findsNothing);

    // Changing the field clears what the server said about it.
    fail = false;
    await _type(tester, 'protein', '27');
    expect(find.text('proteinG must be 0 to 500.'), findsNothing);
  });

  testWidgets('a taken name shows under Name', (tester) async {
    final repo = FakeAdminRepository(
      createFood: (_) async => throw const ApiException(
        'FOOD_NAME_TAKEN',
        'A food with that name already exists.',
      ),
    );
    await _pump(tester, repo);
    await _fillRequired(tester);

    await _pressSave(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('admin.food.name.box')),
        matching: find.text('A food with that name already exists.'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('error')), findsNothing);
  });

  testWidgets('any other failure shows above Save', (tester) async {
    final repo = FakeAdminRepository(createFood: (_) async => throw refused);
    await _pump(tester, repo);
    await _fillRequired(tester);

    await _pressSave(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('error')),
        matching: find.text('The server said no.'),
      ),
      findsOneWidget,
    );
    expect(find.byType(FoodFormScreen), findsOneWidget);
  });

  testWidgets('back with something typed asks before discarding', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository());
    await _type(tester, 'name', 'Turon');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discard.confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(FoodFormScreen), findsNothing);
  });

  group('editing', () {
    // 4·28 + 4·4 + 9·21 = 317: calories worked out, not a label's.
    final worked = sampleFood(
      id: 12,
      name: 'Chicken adobo',
      category: 'filipino',
      foodType: 'home',
      servingDesc: '1 cup',
      kcal: 317,
      proteinG: 28,
      carbsG: 4,
      fatG: 21,
      sodiumMg: 870.5,
    );

    testWidgets('opens filled in, calories empty when worked out', (
      tester,
    ) async {
      await _pump(tester, FakeAdminRepository(), food: worked);

      expect(find.text('Edit food'), findsOneWidget);
      expect(find.text('Chicken adobo'), findsOneWidget);
      expect(find.text('1 cup'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('protein')).controller!.text,
        '28',
      );
      expect(
        tester.widget<TextField>(_field('sodium')).controller!.text,
        '870.5',
      );
      expect(tester.widget<TextField>(_field('fiber')).controller!.text, '');
      expect(tester.widget<TextField>(_field('kcal')).controller!.text, '');
    });

    testWidgets("a label's calories are kept in the box", (tester) async {
      await _pump(
        tester,
        FakeAdminRepository(),
        food: sampleFood(kcal: 350, proteinG: 28, carbsG: 4, fatG: 21),
      );

      expect(tester.widget<TextField>(_field('kcal')).controller!.text, '350');
    });

    testWidgets('an untouched edit form leaves without asking', (tester) async {
      await _pump(tester, FakeAdminRepository(), food: worked);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.byType(FoodFormScreen), findsNothing);
    });

    testWidgets('Save patches the food and says so', (tester) async {
      final repo = FakeAdminRepository();
      await _pump(tester, repo, food: worked);
      final listCalls = repo.foodsCalls.length;

      await _type(tester, 'fat', '20');
      await _pressSave(tester);

      final call = repo.updateFoodCalls.single;
      expect(call.id, 12);
      expect(call.input.fatG, 20);
      expect(call.input.kcal, isNull);
      expect(call.input.sodiumMg, 870.5);
      expect(find.byType(FoodFormScreen), findsNothing);
      expect(find.text('Food saved.'), findsOneWidget);
      expect(repo.foodsCalls.length, greaterThan(listCalls));
    });

    testWidgets('Save keeps what the food contains', (tester) async {
      final repo = FakeAdminRepository();
      await _pump(
        tester,
        repo,
        food: sampleFood(contains: const ['pork', 'egg']),
      );

      await _type(tester, 'fat', '20');
      await _pressSave(tester);

      expect(repo.updateFoodCalls.single.input.contains, ['pork', 'egg']);
    });

    testWidgets('Hide food asks first; Keep leaves it shown', (tester) async {
      final repo = FakeAdminRepository();
      await _pump(tester, repo, food: worked);

      await _tap(tester, find.byKey(const Key('admin.food.hide')));

      expect(find.text('Hide Chicken adobo?'), findsOneWidget);
      expect(
        find.text(
          'It leaves food search, Recents and Snap a meal. Meals already '
          'logged keep it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('admin.hideFood.cancel')));
      await tester.pumpAndSettle();

      expect(repo.hideFoodCalls, isEmpty);
    });

    testWidgets('a confirmed Hide food hides it', (tester) async {
      final repo = FakeAdminRepository();
      await _pump(tester, repo, food: worked);
      final listCalls = repo.foodsCalls.length;

      await _tap(tester, find.byKey(const Key('admin.food.hide')));
      await tester.tap(find.byKey(const Key('admin.hideFood.confirm')));
      await tester.pumpAndSettle();

      expect(repo.hideFoodCalls, [12]);
      expect(find.text('Food hidden.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('admin.food.show')));
      expect(find.byKey(const Key('admin.food.show')), findsOneWidget);
      expect(repo.foodsCalls.length, greaterThan(listCalls));
    });

    testWidgets('Show food shows it again, without asking', (tester) async {
      final repo = FakeAdminRepository();
      await _pump(tester, repo, food: sampleFood(id: 12, hidden: true));

      await _tap(tester, find.byKey(const Key('admin.food.show')));

      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.showFoodCalls, [12]);
      expect(find.text('Food shown.'), findsOneWidget);
    });

    testWidgets('a failed Hide says why', (tester) async {
      final repo = FakeAdminRepository(hideFood: (_) async => throw refused);
      await _pump(tester, repo, food: worked);

      await _tap(tester, find.byKey(const Key('admin.food.hide')));
      await tester.tap(find.byKey(const Key('admin.hideFood.confirm')));
      await tester.pumpAndSettle();

      expect(find.text('The server said no.'), findsOneWidget);
      expect(find.byKey(const Key('admin.food.hide')), findsOneWidget);
    });

    testWidgets('leaving during a save keeps the page below', (tester) async {
      final pending = Completer<AdminFood>();
      final repo = FakeAdminRepository(updateFood: (_, _) => pending.future);
      await _pump(tester, repo, food: worked);

      await _type(tester, 'fat', '20');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FoodFormScreen), findsNothing);

      pending.complete(sampleFood(id: 12));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(find.text('Food saved.'), findsOneWidget);
    });

    testWidgets('Hide food is off while a save runs', (tester) async {
      final pending = Completer<AdminFood>();
      final repo = FakeAdminRepository(updateFood: (_, _) => pending.future);
      await _pump(tester, repo, food: worked);

      await _type(tester, 'fat', '20');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pump();

      expect(
        tester
            .widget<FsButton>(find.byKey(const Key('admin.food.hide')))
            .onPressed,
        isNull,
      );
      pending.complete(sampleFood(id: 12));
      await tester.pumpAndSettle();
    });

    testWidgets('Show food is off while a save runs', (tester) async {
      final pending = Completer<AdminFood>();
      final repo = FakeAdminRepository(updateFood: (_, _) => pending.future);
      await _pump(tester, repo, food: sampleFood(id: 12, hidden: true));

      await _type(tester, 'fat', '20');
      await tester.tap(find.byKey(const Key('save')));
      await tester.pump();

      expect(
        tester
            .widget<FsButton>(find.byKey(const Key('admin.food.show')))
            .onPressed,
        isNull,
      );
      pending.complete(sampleFood(id: 12));
      await tester.pumpAndSettle();
    });

    testWidgets('Save is off while Hide or Show runs', (tester) async {
      final pending = Completer<AdminFood>();
      final repo = FakeAdminRepository(showFood: (_) => pending.future);
      await _pump(tester, repo, food: sampleFood(id: 12, hidden: true));

      await _type(tester, 'fat', '20');
      expect(_save(tester), isNotNull);
      await tester.ensureVisible(find.byKey(const Key('admin.food.show')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin.food.show')));
      await tester.pump();

      expect(_save(tester), isNull);
      pending.complete(sampleFood(id: 12));
      await tester.pumpAndSettle();
      expect(_save(tester), isNotNull);
    });
  });

  testWidgets('a Meals row opens its food to edit', (tester) async {
    final container = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          FakeAdminRepository(
            foods: (_, _, _) async => foodsPage([sampleFood(id: 12)]),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: fsLightTheme(),
          home: const Scaffold(body: MealsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin.food.12')));
    await tester.pumpAndSettle();

    expect(find.text('Edit food'), findsOneWidget);
  });

  testWidgets("Content's + on Meals opens an empty form", (tester) async {
    final container = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(FakeAdminRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: fsLightTheme(),
          home: const Scaffold(body: ContentScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FsSegmented),
        matching: find.text('Meals'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin.content.add')));
    await tester.pumpAndSettle();

    expect(find.text('Add food'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      FakeAdminRepository(),
      food: sampleFood(
        name: 'Pancit canton with lechon kawali and a long name',
        servingDesc: '1 plate (350 g) with sauce',
      ),
      textScale: 2.0,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('admin.food.hide')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(tester, FakeAdminRepository(), dark: true);

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Add food'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets(
    'local-meal chips, and the rice switch once a main meal is chosen',
    (tester) async {
      await _pump(tester, FakeAdminRepository());
      await tester.ensureVisible(find.text('SUGGEST AS A LOCAL MEAL'));
      for (final meal in ['Breakfast', 'Lunch', 'Dinner', 'Snack']) {
        expect(find.text(meal), findsOneWidget, reason: meal);
      }
      expect(find.byKey(const Key('admin.food.suggest.rice')), findsNothing);
      await _tap(tester, find.byKey(const Key('admin.food.suggest.snack')));
      expect(
        find.byKey(const Key('admin.food.suggest.rice')),
        findsNothing,
        reason: 'a snack never comes with rice',
      );
      await _tap(tester, find.byKey(const Key('admin.food.suggest.lunch')));
      expect(find.text('Served with 1 cup rice'), findsOneWidget);
    },
  );

  testWidgets(
    'Save sends the chosen meals in meal order, and the rice switch',
    (tester) async {
      final repo = FakeAdminRepository();
      await _pump(tester, repo);
      await _fillRequired(tester);
      await _tap(tester, find.byKey(const Key('admin.food.suggest.dinner')));
      await _tap(tester, find.byKey(const Key('admin.food.suggest.breakfast')));
      await _tap(tester, find.byKey(const Key('admin.food.suggest.rice')));
      await _pressSave(tester);
      final sent = repo.createFoodCalls.single;
      expect(sent.suggestMeals, ['breakfast', 'dinner']);
      expect(sent.suggestWithRice, isTrue);
    },
  );

  testWidgets('rice is not sent once no main meal is chosen', (tester) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo);
    await _fillRequired(tester);
    await _tap(tester, find.byKey(const Key('admin.food.suggest.lunch')));
    await _tap(tester, find.byKey(const Key('admin.food.suggest.rice')));
    await _tap(tester, find.byKey(const Key('admin.food.suggest.lunch')));
    await _tap(tester, find.byKey(const Key('admin.food.suggest.snack')));
    await _pressSave(tester);
    expect(repo.createFoodCalls.single.suggestMeals, ['snack']);
    expect(repo.createFoodCalls.single.suggestWithRice, isFalse);
  });

  testWidgets("an edit opens on the food's suggestions and sends them back", (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pump(
      tester,
      repo,
      food: sampleFood(
        suggestMeals: const ['lunch', 'dinner'],
        suggestWithRice: true,
      ),
    );
    await tester.ensureVisible(
      find.byKey(const Key('admin.food.suggest.rice')),
    );
    expect(
      tester
          .widget<FsChip>(find.byKey(const Key('admin.food.suggest.lunch')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FsChip>(find.byKey(const Key('admin.food.suggest.snack')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('admin.food.suggest.rice')),
          )
          .value,
      isTrue,
    );
    await _type(tester, 'fat', '20');
    await _pressSave(tester);
    final sent = repo.updateFoodCalls.single.input;
    expect(
      [sent.suggestMeals, sent.suggestWithRice],
      [
        ['lunch', 'dinner'],
        true,
      ],
    );
  });

  for (final dark in [false, true]) {
    testWidgets(
      'the local-meal choices fit a 320 dp phone at 2x text (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          FakeAdminRepository(),
          food: sampleFood(
            suggestMeals: const ['breakfast', 'lunch', 'dinner', 'snack'],
            suggestWithRice: true,
          ),
          textScale: 2.0,
          dark: dark,
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('admin.food.suggest.rice')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('a hidden food is not suggested', () {
    const note = "Hidden foods aren't suggested until shown again.";

    testWidgets('editing a hidden food says so under the local-meal choices', (tester) async {
      await _pump(
        tester,
        FakeAdminRepository(),
        food: sampleFood(id: 12, hidden: true, suggestMeals: const ['lunch'], suggestWithRice: true),
      );
      expect(find.text(note), findsOneWidget);
      // Below the choices, above Show food.
      final y = tester.getTopLeft(find.text(note)).dy;
      expect(y, greaterThan(tester.getTopLeft(find.byKey(const Key('admin.food.suggest.lunch'))).dy));
      expect(y, lessThan(tester.getTopLeft(find.byKey(const Key('admin.food.show'))).dy));
      // The chips the food keeps are left as they are.
      expect(tester.widget<FsChip>(find.byKey(const Key('admin.food.suggest.lunch'))).selected, isTrue);
    });

    testWidgets('a shown food has no such line', (tester) async {
      await _pump(tester, FakeAdminRepository(), food: sampleFood(id: 12, suggestMeals: const ['lunch']));
      expect(find.text(note), findsNothing);
    });

    testWidgets('a new food has no such line', (tester) async {
      await _pump(tester, FakeAdminRepository());
      expect(find.text(note), findsNothing);
    });

    testWidgets('Show food takes the line away', (tester) async {
      await _pump(tester, FakeAdminRepository(), food: sampleFood(id: 12, hidden: true));
      await _tap(tester, find.byKey(const Key('admin.food.show')));
      expect(find.text(note), findsNothing);
    });
  });

  group('Contains', () {
    const helper = 'Used to skip dishes for trainees who avoid these foods.';
    const labels = {
      'pork': 'Pork',
      'beef': 'Beef',
      'chicken': 'Chicken',
      'fish': 'Fish',
      'shellfish': 'Shrimp & shellfish',
      'egg': 'Egg',
    };

    FsChip chip(WidgetTester tester, String group) =>
        tester.widget<FsChip>(find.byKey(Key('admin.food.contains.$group')));

    testWidgets('a new food shows the heading, six chips and the helper', (
      tester,
    ) async {
      await _pump(tester, FakeAdminRepository());
      await tester.ensureVisible(find.text('CONTAINS'));
      expect(find.text('CONTAINS'), findsOneWidget);
      for (final MapEntry(key: group, value: label) in labels.entries) {
        final finder = find.byKey(Key('admin.food.contains.$group'));
        expect(finder, findsOneWidget, reason: group);
        expect(chip(tester, group).label, label);
        expect(chip(tester, group).selected, isFalse, reason: group);
      }
      expect(find.text(helper), findsOneWidget);
      // Below the local-meal choices.
      expect(
        tester.getTopLeft(find.text('CONTAINS')).dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const Key('admin.food.suggest.lunch')))
              .dy,
        ),
      );
    });

    testWidgets('Save sends the tapped groups in group order', (tester) async {
      final repo = FakeAdminRepository();
      await _pump(tester, repo);
      await _fillRequired(tester);
      await _tap(tester, find.byKey(const Key('admin.food.contains.egg')));
      await _tap(tester, find.byKey(const Key('admin.food.contains.pork')));
      expect(chip(tester, 'egg').selected, isTrue);
      await _pressSave(tester);
      expect(repo.createFoodCalls.single.contains, ['pork', 'egg']);
    });

    testWidgets("an edit opens on the food's tags and sends them back", (
      tester,
    ) async {
      final repo = FakeAdminRepository();
      await _pump(
        tester,
        repo,
        food: sampleFood(id: 12, contains: const ['fish']),
      );
      await tester.ensureVisible(
        find.byKey(const Key('admin.food.contains.fish')),
      );
      expect(chip(tester, 'fish').selected, isTrue);
      expect(chip(tester, 'pork').selected, isFalse);
      await _type(tester, 'fat', '20');
      await _pressSave(tester);
      expect(repo.updateFoodCalls.single.input.contains, ['fish']);
    });

    testWidgets('a changed tag is an unsaved change', (tester) async {
      await _pump(
        tester,
        FakeAdminRepository(),
        food: sampleFood(id: 12, contains: const ['fish']),
      );
      await _tap(tester, find.byKey(const Key('admin.food.contains.beef')));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
    });

    testWidgets('a tag tapped twice is no change', (tester) async {
      await _pump(
        tester,
        FakeAdminRepository(),
        food: sampleFood(id: 12, contains: const ['fish']),
      );
      await _tap(tester, find.byKey(const Key('admin.food.contains.fish')));
      await _tap(tester, find.byKey(const Key('admin.food.contains.fish')));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.byType(FoodFormScreen), findsNothing);
    });

    testWidgets("the server's refusal of contains shows under the chips", (
      tester,
    ) async {
      const message = 'contains must list pork, beef, chicken, fish, '
          'shellfish or egg.';
      final repo = FakeAdminRepository(
        createFood: (_) async => throw const ApiException(
          'INVALID_ADMIN_FIELD',
          message,
          details: [
            {'field': 'contains'},
          ],
        ),
      );
      await _pump(tester, repo);
      await _fillRequired(tester);
      await _tap(tester, find.byKey(const Key('admin.food.contains.pork')));

      await _pressSave(tester);

      expect(find.byType(FoodFormScreen), findsOneWidget);
      expect(find.byKey(const Key('error')), findsNothing);
      await tester.ensureVisible(find.text(message));
      await tester.pumpAndSettle();
      final y = tester.getTopLeft(find.text(message)).dy;
      expect(
        y,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const Key('admin.food.contains.egg')))
              .dy,
        ),
      );
      expect(y, lessThan(tester.getTopLeft(find.text(helper)).dy));

      // Changing a tag clears what the server said.
      await _tap(tester, find.byKey(const Key('admin.food.contains.beef')));
      expect(find.text(message), findsNothing);
    });

    testWidgets('the chips fit a 320 dp phone at 2x text', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        FakeAdminRepository(),
        food: sampleFood(contains: const ['pork', 'shellfish', 'egg']),
        textScale: 2.0,
      );
      await tester.scrollUntilVisible(
        find.text(helper),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
