import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/meals_tab.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/widgets/admin_widgets.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/dish_photo.dart';

import 'helpers/fake_admin_repository.dart';
import 'helpers/fake_dish_photos.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  bool dark = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
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
        home: const Scaffold(body: MealsTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

List<AdminFood> _rows(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    sampleFood(id: 100 + i, name: 'Food $i'),
];

void main() {
  testWidgets('asks for the shown foods first, with all three counts', (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      foods: (_, _, _) async =>
          foodsPage(_rows(2), shown: 412, hidden: 3, suggested: 35),
    );
    await _pump(tester, repo);

    expect(repo.foodsCalls, [(show: 'shown', q: '', page: 1)]);
    expect(find.text('Shown (412)'), findsOneWidget);
    expect(find.text('Hidden (3)'), findsOneWidget);
    expect(find.text('Suggested (35)'), findsOneWidget);
    expect(find.text('Search foods'), findsOneWidget);
  });

  testWidgets('a row shows the name, serving, calories and type', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      FakeAdminRepository(
        foods: (_, _, _) async => foodsPage([
          sampleFood(
            id: 12,
            name: 'Chicken adobo',
            servingDesc: '1 cup',
            kcal: 1320,
            foodType: 'home',
          ),
          sampleFood(
            id: 13,
            name: 'Turon',
            servingDesc: null,
            kcal: 180,
            foodType: 'snack_sweet',
            hidden: true,
          ),
        ]),
      ),
    );

    expect(find.text('Chicken adobo'), findsOneWidget);
    expect(find.text('1 cup · 1,320 kcal'), findsOneWidget);
    expect(find.text('Home-cooked'), findsOneWidget);
    expect(find.text('180 kcal'), findsOneWidget);
    expect(find.text('Snack & sweet'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin.food.13')),
        matching: find.descendant(
          of: find.byType(StatusTag),
          matching: find.text('Hidden'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin.food.12')),
        matching: find.byType(StatusTag),
      ),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('Turon, 180 kcal, Snack & sweet, Hidden'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the Hidden chip asks for hidden foods', (tester) async {
    final repo = FakeAdminRepository(
      foods: (_, _, _) async => foodsPage(_rows(2)),
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Hidden (3)'));
    await tester.pumpAndSettle();

    expect(repo.foodsCalls.last, (show: 'hidden', q: '', page: 1));
  });

  testWidgets('typing searches once, 300 ms after the last key', (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      foods: (_, _, _) async => foodsPage(_rows(2)),
    );
    await _pump(tester, repo);

    final field = find.byKey(const Key('admin.foods.search'));
    for (final text in ['a', 'ad', 'ado']) {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repo.foodsCalls, hasLength(1), reason: 'still typing');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repo.foodsCalls.last, (show: 'shown', q: 'ado', page: 1));
  });

  testWidgets('scrolling near the end loads the next page', (tester) async {
    final repo = FakeAdminRepository(
      foods: (_, _, page) async {
        final start = (page - 1) * 30;
        final count = (40 - start).clamp(0, 30);
        return foodsPage(_rows(count, from: start), page: page, total: 40);
      },
    );
    await _pump(tester, repo);

    await tester.scrollUntilVisible(
      find.text('Food 29'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(repo.foodsCalls.map((c) => c.page), [1, 2]);
  });

  testWidgets('a search with no match offers Clear search', (tester) async {
    final repo = FakeAdminRepository(
      foods: (_, q, _) async =>
          q.isEmpty ? foodsPage(_rows(2)) : foodsPage(const []),
    );
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('admin.foods.search')), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('No foods match "zzz".'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.foods.clear')));
    await tester.pumpAndSettle();

    expect(repo.foodsCalls.last, (show: 'shown', q: '', page: 1));
    expect(find.text('Food 0'), findsOneWidget);
  });

  testWidgets('an empty list says so for each chip', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(foods: (_, _, _) async => foodsPage(const [])),
    );
    expect(find.text('No foods yet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.foods.chip.hidden')));
    await tester.pumpAndSettle();

    expect(find.text('No hidden foods.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.foods.chip.suggested')));
    await tester.pumpAndSettle();

    expect(find.text('No suggested foods.'), findsOneWidget);
  });

  testWidgets('a failed load offers Try again', (tester) async {
    var fail = true;
    final repo = FakeAdminRepository(
      foods: (_, _, _) async {
        if (fail) throw refused;
        return foodsPage(_rows(1));
      },
    );
    await _pump(tester, repo);

    expect(find.text('The server said no.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('admin.foods.retry')));
    await tester.pumpAndSettle();

    expect(find.text('Food 0'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      FakeAdminRepository(
        foods: (_, _, _) async => foodsPage([
          sampleFood(
            name: 'Pancit canton with lechon kawali and a long name',
            servingDesc: '1 plate (350 g) with sauce',
            foodType: 'canned_instant',
            kcal: 1250,
            hidden: true,
          ),
          ..._rows(4),
        ]),
      ),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(foods: (_, _, _) async => foodsPage(_rows(2))),
      dark: true,
    );

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Food 0'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('the Suggested chip asks for suggested foods', (tester) async {
    final repo = FakeAdminRepository(
      foods: (_, _, _) async => foodsPage(_rows(2)),
    );
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('admin.foods.chip.suggested')));
    await tester.pumpAndSettle();

    expect(repo.foodsCalls.last, (show: 'suggested', q: '', page: 1));
  });

  testWidgets(
    'a suggested food is labelled so, on screen and to a screen reader',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        FakeAdminRepository(
          foods: (_, _, _) async => foodsPage([
            sampleFood(
              id: 12,
              name: 'Tinolang manok',
              servingDesc: '1 bowl (350 g)',
              kcal: 260,
              foodType: 'home',
              suggestMeals: const ['lunch', 'dinner'],
              suggestWithRice: true,
            ),
            sampleFood(
              id: 13,
              name: 'Turon',
              servingDesc: null,
              kcal: 180,
              foodType: 'snack_sweet',
            ),
          ]),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('admin.food.12')),
          matching: find.descendant(
            of: find.byType(StatusTag),
            matching: find.text('Suggested'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('admin.food.13')),
          matching: find.byType(StatusTag),
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(
          'Tinolang manok, 1 bowl (350 g) · 260 kcal, Home-cooked, Suggested',
        ),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'a suggested, hidden row fits a 320 dp phone at 2x text (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          FakeAdminRepository(
            foods: (_, _, _) async => foodsPage([
              sampleFood(
                name: 'Ginataang tulingan (frigate tuna in coconut milk)',
                servingDesc: '1 fish piece with sauce (210 g)',
                kcal: 293,
                hidden: true,
                suggestMeals: const ['lunch', 'dinner'],
                suggestWithRice: true,
              ),
              ..._rows(3),
            ]),
          ),
          textScale: 2.0,
          dark: dark,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a hidden food is Hidden, not Suggested: the server never suggests it', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      FakeAdminRepository(
        foods: (_, _, _) async => foodsPage([
          sampleFood(
            id: 12,
            name: 'Tinolang manok',
            servingDesc: '1 bowl (350 g)',
            kcal: 260,
            foodType: 'home',
            hidden: true,
            suggestMeals: const ['lunch', 'dinner'],
            suggestWithRice: true,
          ),
        ]),
      ),
    );
    Finder tag(String text) => find.descendant(
      of: find.byKey(const ValueKey('admin.food.12')),
      matching: find.descendant(of: find.byType(StatusTag), matching: find.text(text)),
    );
    expect(tag('Hidden'), findsOneWidget);
    expect(tag('Suggested'), findsNothing);
    expect(find.bySemanticsLabel('Tinolang manok, 1 bowl (350 g) · 260 kcal, Home-cooked, Hidden'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a row starts with its dish photo, 40 x 40, or the leaf tile', (tester) async {
    final asked = fakeDishPhotos();
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      FakeAdminRepository(
        foods: (_, _, _) async => foodsPage([
          sampleFood(id: 12, name: 'Chicken adobo', photoUrl: 'http://media.test/storage/foods/a.jpg'),
          sampleFood(id: 13, name: 'Turon'),
        ]),
      ),
    );
    await decodeDishPhotos(tester);

    Finder inRow(int id, Finder matching) =>
        find.descendant(of: find.byKey(ValueKey('admin.food.$id')), matching: matching);

    final photo = inRow(12, find.byType(DishPhoto));
    expect(photo, findsOneWidget);
    expect(tester.widget<DishPhoto>(photo).url, 'http://media.test/storage/foods/a.jpg');
    expect(tester.getSize(photo), const Size(40, 40));
    expect(inRow(12, find.byKey(const Key('dish.photo'))), findsOneWidget);
    expect(asked, ['http://media.test/storage/foods/a.jpg']);
    // At the start of the row, 12 dp before the name.
    expect(tester.getTopRight(photo).dx + 12, tester.getTopLeft(inRow(12, find.text('Chicken adobo'))).dx);

    final leaf = inRow(13, find.byType(DishPhoto));
    expect(tester.widget<DishPhoto>(leaf).url, isNull);
    expect(tester.getSize(leaf), const Size(40, 40));
    expect(inRow(13, find.byKey(const Key('dish.leaf'))), findsOneWidget);

    // One spoken label per row, as before: the photo adds nothing.
    expect(find.bySemanticsLabel('Chicken adobo, 1 cup · 320 kcal, Home-cooked'), findsOneWidget);
    expect(find.bySemanticsLabel('Turon, 1 cup · 320 kcal, Home-cooked'), findsOneWidget);
    handle.dispose();
  });
}
