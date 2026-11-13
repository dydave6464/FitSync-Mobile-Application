import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/meal_ideas_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_plate_sheet.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/meal_idea_rows.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'helpers/meal_suggestion_fixtures.dart';
import 'nutrition_controller_test.dart' show FakeNutritionRepository, emptyDay;

class _Profile extends ProfileNotifier {
  @override
  Future<Profile> build() async => const Profile(
    userId: 1, email: 'juan@example.com', fullName: 'Juan', onboardingCompleted: true,
    isPremium: false, notificationsEnabled: true, equipment: [], injuries: [],
  );
}

/// Holds each log until [logHold] completes, so a test can act mid-save.
/// With [refuseRice], the rice is then refused.
class _HeldLog extends FakeNutritionRepository {
  Completer<void>? logHold;
  bool refuseRice = false;

  @override
  Future<FoodEntry> logEntry({
    required String date, required String mealType, required double servings, required Food food, String? clientId,
  }) async {
    if (logHold != null) await logHold!.future;
    if (refuseRice && food.name == 'White rice') {
      calls.add('log $date $mealType ${food.name} x$servings');
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
    return super.logEntry(date: date, mealType: mealType, servings: servings, food: food, clientId: clientId);
  }
}

/// Refuses the plate's rice once, as a dropped connection would after the
/// dish went through.
class _RiceFailsOnce extends FakeNutritionRepository {
  bool _failed = false;

  @override
  Future<FoodEntry> logEntry({
    required String date, required String mealType, required double servings, required Food food, String? clientId,
  }) async {
    if (food.name == 'White rice' && !_failed) {
      _failed = true;
      clientIds.add(clientId);
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
    return super.logEntry(date: date, mealType: mealType, servings: servings, food: food, clientId: clientId);
  }
}

/// Nine lunch plates: Dish 0 … Dish 8.
final _nine = [
  for (var i = 0; i < 9; i++) plateJson(suggestedFoodJson(20 + i, 'Dish $i', '1 serving', 200 + i, 20, 10, 5)),
];

class _Popped {
  PlateLogged? value;
}

Future<(FakeNutritionRepository, _Popped)> _pump(
  WidgetTester tester, {
  FakeNutritionRepository? repo,
  Map<String, MealSuggestions> answers = const {},
  String initialMeal = 'lunch',
  Size size = const Size(390, 1400),
  double textScale = 1,
  bool dark = false,
  bool reduceMotion = false,
}) async {
  final r = repo ?? FakeNutritionRepository();
  r.days[fixtureToday] = emptyDay(fixtureToday);
  r.suggestionsByMeal.addAll(answers);
  final popped = _Popped();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(r),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
      profileProvider.overrideWith(_Profile.new),
    ],
    child: MaterialApp(
      theme: dark ? fsDarkTheme() : fsLightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
        child: child!,
      ),
      // As the Nutrition tab opens the page: a plate it hands back is said
      // here, with Undo.
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final controller = ref.read(nutritionDayProvider.notifier);
              final logged = popped.value = await Navigator.of(context).push<PlateLogged>(
                MaterialPageRoute(builder: (_) => MealIdeasScreen(initialMeal: initialMeal)),
              );
              if (logged != null) {
                showPlateLoggedSnackBar(messenger, controller, logged.meal, logged.entries, screenReader: false);
              }
            },
            child: const Text('home'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('home'));
  await tester.pumpAndSettle();
  return (r, popped);
}

final _lunch = suggestionsAnswer('fits', [plateJson(tinolaJson), plateJson(sinigangJson), plateJson(bangusJson, high: true)],
    share: {'kcal': 650, 'proteinG': 40});
final _dinner = suggestionsAnswer('fits', [plateJson(bangusJson, high: true)], meal: 'dinner', share: {'kcal': 900, 'proteinG': 50});

bool _selected(WidgetTester tester, String meal) => tester.widget<FsChip>(find.byKey(Key('ideas.meal.$meal'))).selected;

/// Drags the sheet a little past half its height and lets go: it closes,
/// its route popping at once, but stays on screen for the rest of its exit.
Future<void> _dragHalfAway(WidgetTester tester) async {
  final height = tester.getSize(find.byType(LogPlateSheet)).height;
  await tester.drag(find.byKey(const Key('sheet.handle')), Offset(0, height * 0.55));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Finder _inSheet(String text) => find.descendant(of: find.byType(LogPlateSheet), matching: find.text(text));

void main() {
  testWidgets('opens on the meal asked for: its buttons, line, plates and footnote', (tester) async {
    await _pump(tester, answers: {'lunch': _lunch});
    expect(find.text('Meal ideas'), findsOneWidget);
    expect([for (final m in mealTypes) _selected(tester, m)], [false, true, false, false]);
    expect(find.byKey(const Key('suggest.subheading')), findsOneWidget);
    expect(find.text('Tinolang manok + 1 cup rice'), findsOneWidget);
    expect(find.byKey(const Key('suggest.row.2')), findsOneWidget);
    expect(find.text("Picked by simple rules from your target and today's log."), findsOneWidget);
  });

  testWidgets('asks for all four meals at once, so a switch shows the other at once', (tester) async {
    final (repo, _) = await _pump(tester, answers: {'lunch': _lunch, 'dinner': _dinner});
    expect(repo.suggestionCalls.toSet(), {'breakfast', 'lunch', 'dinner', 'snack'});
    await tester.tap(find.byKey(const Key('ideas.meal.dinner')));
    await tester.pump();
    expect(find.byKey(const Key('suggest.loading')), findsNothing);
    expect(find.text('Grilled bangus + 1 cup rice'), findsOneWidget);
    expect(_selected(tester, 'dinner'), isTrue);
  });

  testWidgets('three at a time, up to nine; the first new plate takes focus', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, answers: {'lunch': suggestionsAnswer('fits', _nine, share: {'kcal': 650, 'proteinG': 40})});
    expect(find.byKey(const Key('suggest.row.3')), findsNothing);
    await tester.tap(find.byKey(const Key('ideas.more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest.row.5')), findsOneWidget);
    // The focus is on row 3's card, and its own labelled node says so: no
    // unlabelled wrapper node above it.
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(find.descendant(of: find.byKey(const Key('suggest.row.3')), matching: find.byWidget(focused.widget)), findsOneWidget);
    final row = tester.getSemantics(find.byKey(const Key('suggest.row.3')));
    expect(row.label, isNotEmpty);
    expect(row, isSemantics(isButton: true, isFocusable: true, isFocused: true, hasFocusAction: true));
    expect(row.parent, isNot(isSemantics(isFocusable: true)));
    // One keyboard stop per row: Tab goes straight on to row 4.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final next = FocusManager.instance.primaryFocus!.context!;
    expect(find.descendant(of: find.byKey(const Key('suggest.row.4')), matching: find.byWidget(next.widget)), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('suggest.row.3'))), isSemantics(isFocusable: true, isFocused: false));
    await tester.tap(find.byKey(const Key('ideas.more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest.row.8')), findsOneWidget);
    expect(find.byKey(const Key('ideas.more')), findsNothing);
    semantics.dispose();
  });

  testWidgets('a meal button answers a tap 6 dp above or below the rows', (tester) async {
    await _pump(tester, answers: {'lunch': _lunch});
    // At 390 dp the buttons take two rows: Snack starts the second.
    final breakfast = tester.getRect(find.byKey(const Key('ideas.meal.breakfast')));
    final snack = tester.getRect(find.byKey(const Key('ideas.meal.snack')));
    expect(snack.top, greaterThan(breakfast.bottom));
    await tester.tapAt(snack.bottomCenter + const Offset(0, 6));
    await tester.pump();
    expect(_selected(tester, 'snack'), isTrue, reason: 'below the last row');
    await tester.tapAt(breakfast.topCenter - const Offset(0, 6));
    await tester.pump();
    expect(_selected(tester, 'breakfast'), isTrue, reason: 'above the first row');
  });

  testWidgets('switching meal goes back to three', (tester) async {
    await _pump(tester, answers: {
      'lunch': suggestionsAnswer('fits', _nine, share: {'kcal': 650, 'proteinG': 40}),
      'dinner': suggestionsAnswer('fits', _nine, meal: 'dinner', share: {'kcal': 900, 'proteinG': 50}),
    });
    await tester.tap(find.byKey(const Key('ideas.more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ideas.meal.dinner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest.row.3')), findsNothing);
  });

  testWidgets('tapping the meal already picked keeps the plates shown', (tester) async {
    await _pump(tester, answers: {'lunch': suggestionsAnswer('fits', _nine, share: {'kcal': 650, 'proteinG': 40})});
    await tester.tap(find.byKey(const Key('ideas.more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ideas.meal.lunch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest.row.3')), findsOneWidget);
  });

  testWidgets('scrolled to the end, the footnote clears the bottom safe area', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    await _pump(tester, size: const Size(390, 700),
        answers: {'lunch': suggestionsAnswer('fits', _nine, share: {'kcal': 650, 'proteinG': 40})});
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.byKey(const Key('ideas.more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ideas.more')));
      await tester.pumpAndSettle();
    }
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest.row.8')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('ideas.footnote'))).bottom, lessThanOrEqualTo(700 - 34));
  });

  testWidgets('a meal with nothing to suggest says so', (tester) async {
    await _pump(tester, answers: {'lunch': _lunch});
    await tester.tap(find.byKey(const Key('ideas.meal.breakfast')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to suggest for breakfast right now.'), findsOneWidget);
    expect(find.byKey(const Key('ideas.more')), findsNothing);
  });

  testWidgets('a failed meal shows the error line; the buttons still work', (tester) async {
    final repo = FakeNutritionRepository()..failSuggestions = true;
    await _pump(tester, repo: repo);
    expect(find.byKey(const Key('suggest.retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ideas.meal.dinner')));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'dinner'), isTrue);
  });

  testWidgets('Log plate with the sheet open closes the page and hands back the plate', (tester) async {
    final (_, popped) = await _pump(tester, answers: {'lunch': _lunch});
    await tester.tap(find.byKey(const Key('suggest.row.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(find.byType(MealIdeasScreen), findsNothing);
    expect(popped.value!.meal, 'lunch');
    expect(popped.value!.entries, hasLength(2));
  });

  testWidgets('dragged away mid-save: the page stays and says Logged with Undo there', (tester) async {
    final repo = _HeldLog();
    final (_, popped) = await _pump(tester, repo: repo, answers: {'lunch': _lunch});
    await tester.tap(find.byKey(const Key('suggest.row.0')));
    await tester.pumpAndSettle();
    repo.logHold = Completer<void>();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pump();
    final height = tester.getSize(find.byType(LogPlateSheet)).height;
    // The same drag the old section tests used: FsSheetHeader's handle.
    await tester.drag(find.byKey(const Key('sheet.handle')), Offset(0, height * 0.6));
    await tester.pumpAndSettle();
    repo.logHold!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MealIdeasScreen), findsOneWidget);
    expect(popped.value, isNull);
    expect(find.text('Logged to lunch'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('fits a 320 dp phone at 2x text: the buttons wrap, nothing overflows', (tester) async {
    await _pump(tester, answers: {'lunch': _lunch}, size: const Size(320, 1600), textScale: 2);
    expect(tester.takeException(), isNull);
    final first = tester.getTopLeft(find.byKey(const Key('ideas.meal.breakfast'))).dy;
    final last = tester.getTopLeft(find.byKey(const Key('ideas.meal.snack'))).dy;
    expect(last, greaterThan(first), reason: 'a second line of buttons');
  });

  // Moved from the tab's old Suggested section: the rows live here now.
  group('the rows', () {
    testWidgets('fits: the plates for the meal, with what is left', (tester) async {
      await _pump(tester, answers: {'lunch': _lunch});
      for (final text in [
        'Local',
        'Fits the ~650 kcal and 40 g protein left for lunch',
        'Tinolang manok + 1 cup rice',
        '1 bowl + 1 cup · 466 kcal · 29 g protein',
        'Sinigang na bangus (milkfish sour soup) + 1 cup rice',
        '1 bowl with broth + 1 cup · 401 kcal · 26 g protein',
        'Grilled bangus + 1 cup rice',
        '1 piece + 1 cup · 412 kcal · 38 g protein',
        'High protein',
        "Picked by simple rules from your target and today's log.",
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('spaced 10 under the line and 8 apart, each at least 48 dp', (tester) async {
      await _pump(tester, answers: {'lunch': _lunch});
      Rect r(Finder f) => tester.getRect(f);
      final sub = r(find.byKey(const Key('suggest.subheading')));
      final first = r(find.byKey(const Key('suggest.row.0')));
      final second = r(find.byKey(const Key('suggest.row.1')));
      expect(first.top - sub.bottom, closeTo(10, 0.01));
      expect(second.top - first.bottom, closeTo(8, 0.01));
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(find.byKey(Key('suggest.row.$i'))).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets("the protein figure is in the Protein bar's green, with its number", (tester) async {
      await _pump(tester, answers: {'lunch': _lunch});
      final meta = find.byKey(const Key('suggest.meta.0'));
      final protein = (tester.widget<Text>(meta).textSpan! as TextSpan).children!.last as TextSpan;
      expect(protein.text, '29 g protein');
      expect(protein.style!.color, tester.element(meta).fs.accentText);
    });

    testWidgets('no target: says how to fit them to the day', (tester) async {
      await _pump(tester, answers: {'lunch': suggestionsAnswer('no_target', [plateJson(tinolaJson)])});
      expect(find.text('Add your weight and height in Profile to fit these to your day.'), findsOneWidget);
      expect(find.text('Tinolang manok + 1 cup rice'), findsOneWidget);
    });

    testWidgets("today's calories reached: light options, without rice", (tester) async {
      await _pump(tester, answers: {'lunch': suggestionsAnswer('reached', [plateJson(eggJson, rice: false, high: true)])});
      expect(find.text("You've reached today's calories. Light options:"), findsOneWidget);
      expect(find.text('Hard-boiled egg'), findsOneWidget);
      expect(find.text('1 large · 78 kcal · 6 g protein'), findsOneWidget);
    });

    testWidgets('each row is one button saying the plate, with a Log hint', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, answers: {'lunch': _lunch});
      expect(
        tester.getSemantics(find.byKey(const Key('suggest.row.0'))),
        isSemantics(
          label: 'Tinolang manok with 1 cup rice, 466 kilocalories, 29 grams protein',
          hint: 'Log to lunch',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('suggest.row.2'))),
        isSemantics(
          label: 'Grilled bangus with 1 cup rice, 412 kilocalories, 38 grams protein, high protein',
          hint: 'Log to lunch',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the rows cross-fade over 200 ms', (tester) async {
      await _pump(tester, answers: {'lunch': _lunch});
      final switcher = tester.widget<AnimatedSwitcher>(
        find.ancestor(of: find.byKey(const Key('suggest.subheading')), matching: find.byType(AnimatedSwitcher)).first,
      );
      expect(switcher.duration, const Duration(milliseconds: 200));
    });

    testWidgets('with reduced motion the rows switch at once', (tester) async {
      await _pump(tester, answers: {'lunch': _lunch}, reduceMotion: true);
      expect(find.byKey(const Key('suggest.subheading')), findsOneWidget);
      expect(
        find.ancestor(of: find.byKey(const Key('suggest.subheading')), matching: find.byType(AnimatedSwitcher)),
        findsNothing,
      );
    });

    for (final dark in [false, true]) {
      testWidgets('rows fit a 320 dp phone at 2x text (${dark ? 'dark' : 'light'})', (tester) async {
        final long = plateJson(
          suggestedFoodJson(20, 'Ginataang tulingan (frigate tuna in coconut milk)', '1 fish piece with sauce (210 g)',
              293, 26.3, 7.5, 17.9),
          high: true,
        );
        await _pump(
          tester,
          answers: {
            'lunch': suggestionsAnswer('fits', [long, plateJson(tinolaJson), plateJson(bangusJson, high: true)],
                share: {'kcal': 1150, 'proteinG': 47.5}),
          },
          size: const Size(320, 3200),
          textScale: 2,
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 3; i++) {
          expect(tester.getSize(find.byKey(Key('suggest.row.$i'))).height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.byKey(const Key('suggest.row.0')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('logPlate.log')), findsOneWidget);
      });
    }
  });

  group('logging a plate from a row', () {
    testWidgets('tapping a row opens Log to Lunch: each item, the plate total and Log plate', (tester) async {
      await _pump(tester, answers: {'lunch': _lunch});
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      for (final text in [
        'Log to Lunch',
        'Tinolang manok', '1 bowl (350 g)', '260 kcal', 'Protein 26 g · Carbs 8 g · Fat 14 g',
        'White rice', '206 kcal', 'Protein 3 g · Carbs 45 g · Fat 0 g',
        'Plate total', '466 kcal', 'Protein 29 g · Carbs 53 g · Fat 14 g',
        'Log plate',
      ]) {
        expect(_inSheet(text), findsOneWidget, reason: text);
      }
      // The rice line says the cups on the plate ("1 cup" is a rice chip too).
      expect(find.descendant(of: find.byKey(const Key('logPlate.item.1')), matching: find.text('1 cup')), findsOneWidget);
    });

    testWidgets('one protein figure for one plate: the total is in whole grams, as the row is', (tester) async {
      final adobo = plateJson(suggestedFoodJson(14, 'Adobong manok', '1 serving (150 g)', 260, 26.3, 8, 14));
      await _pump(tester, answers: {'lunch': suggestionsAnswer('fits', [adobo], share: {'kcal': 650, 'proteinG': 40})});
      expect(find.text('1 serving + 1 cup · 466 kcal · 29 g protein'), findsOneWidget);
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('logPlate.total')),
          matching: find.text('Protein 29 g · Carbs 53 g · Fat 14 g'),
        ),
        findsOneWidget,
      );
      // The dish's own line keeps its decimal, as Log food does.
      expect(
        find.descendant(
          of: find.byKey(const Key('logPlate.item.14')),
          matching: find.text('Protein 26.3 g · Carbs 8 g · Fat 14 g'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Log plate logs the dish and its rice, each with its own key; back home, Undo takes both off', (tester) async {
      final (repo, _) = await _pump(tester, answers: {'lunch': _lunch});
      final asked = repo.suggestionCalls.length;
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pumpAndSettle();

      expect(
        repo.calls,
        containsAllInOrder(['log $fixtureToday lunch Tinolang manok x1.0', 'log $fixtureToday lunch White rice x1.0']),
      );
      expect(repo.clientIds, hasLength(2));
      expect(repo.clientIds.every((id) => id != null), isTrue);
      expect(repo.clientIds.toSet(), hasLength(2));
      expect(find.byType(LogPlateSheet), findsNothing);
      expect(find.byType(MealIdeasScreen), findsNothing);
      // The page closed; the home screen says so.
      expect(find.text('home'), findsOneWidget);
      expect(find.text('Logged to lunch'), findsOneWidget);
      // The day changed, so the suggestions were asked for again.
      expect(repo.suggestionCalls.length, greaterThan(asked));

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.calls, containsAll(['delete 100', 'delete 101']));
      expect(repo.dayOf(fixtureToday).entries, isEmpty);
    });

    testWidgets('a failed log stays in the sheet with Retry, which sends the same keys', (tester) async {
      final repo = _RiceFailsOnce();
      await _pump(tester, repo: repo, answers: {'lunch': _lunch});
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pumpAndSettle();

      expect(find.byType(LogPlateSheet), findsOneWidget);
      expect(
        find.descendant(of: find.byType(LogPlateSheet), matching: find.textContaining("Couldn't log the plate.")),
        findsOneWidget,
      );
      expect(_inSheet('Retry'), findsOneWidget);
      final first = [...repo.clientIds];
      expect(first, hasLength(2));

      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pumpAndSettle();
      expect(repo.clientIds, [...first, ...first]);
      expect(find.byType(LogPlateSheet), findsNothing);
      // The dish saved the first time came back rather than being saved again.
      expect(repo.dayOf(fixtureToday).entries.where((e) => e.name == 'Tinolang manok'), hasLength(1));
      expect(repo.dayOf(fixtureToday).entries.where((e) => e.name == 'White rice'), hasLength(1));
    });

    testWidgets('dragged away mid-save, a refused rice still says so, on the page', (tester) async {
      final repo = _HeldLog();
      await _pump(tester, repo: repo, answers: {'lunch': _lunch});
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      repo
        ..logHold = Completer<void>()
        ..refuseRice = true;
      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pump();
      await tester.drag(find.byKey(const Key('sheet.handle')), const Offset(0, 600));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LogPlateSheet), findsNothing);

      repo.logHold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MealIdeasScreen), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.textContaining("Couldn't log the plate.")),
        findsOneWidget,
      );
      expect(find.text('Logged to lunch'), findsNothing);
    });

    // The sheet stays mounted for its exit animation after a drag, while its
    // route is already popping: a save landing then must not pop the page
    // under it.
    testWidgets('a save landing while the dragged sheet slides away keeps the page', (tester) async {
      final repo = _HeldLog();
      final (_, popped) = await _pump(tester, repo: repo, answers: {'lunch': _lunch});
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      repo.logHold = Completer<void>();
      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pump();
      await _dragHalfAway(tester);
      expect(find.byType(LogPlateSheet), findsOneWidget, reason: 'still sliding away');

      repo.logHold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MealIdeasScreen), findsOneWidget);
      expect(popped.value, isNull);
      expect(find.byType(LogPlateSheet), findsNothing);
      expect(find.text('Logged to lunch'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(
        repo.calls,
        containsAllInOrder(['log $fixtureToday lunch Tinolang manok x1.0', 'log $fixtureToday lunch White rice x1.0']),
      );
    });

    testWidgets('a refused rice landing while the dragged sheet slides away still says so', (tester) async {
      final repo = _HeldLog();
      await _pump(tester, repo: repo, answers: {'lunch': _lunch});
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      repo
        ..logHold = Completer<void>()
        ..refuseRice = true;
      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pump();
      await _dragHalfAway(tester);
      expect(find.byType(LogPlateSheet), findsOneWidget, reason: 'still sliding away');

      repo.logHold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MealIdeasScreen), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.textContaining("Couldn't log the plate.")),
        findsOneWidget,
      );
      expect(find.text('Logged to lunch'), findsNothing);
    });

    testWidgets('a failed refetch after Log plate shows the error line, not the old rows', (tester) async {
      final repo = _HeldLog();
      await _pump(tester, repo: repo, answers: {'lunch': _lunch});
      await tester.tap(find.byKey(const Key('suggest.row.0')));
      await tester.pumpAndSettle();
      // Dragged away mid-save, so the page stays to show the refetch.
      repo.logHold = Completer<void>();
      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pump();
      await tester.drag(find.byKey(const Key('sheet.handle')), const Offset(0, 600));
      await tester.pump(const Duration(seconds: 1));
      // UNKNOWN_ERROR: never retried, so the refetch fails at once.
      repo.failSuggestions = true;
      repo.logHold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Logged to lunch'), findsOneWidget);
      expect(find.text("Couldn't load suggestions."), findsOneWidget);
      expect(find.text('Tinolang manok + 1 cup rice'), findsNothing);

      // Retry from there shows the placeholders, not the old rows, until the
      // new answer comes.
      repo
        ..failSuggestions = false
        ..suggestionsHold = Completer<void>();
      await tester.tap(find.byKey(const Key('suggest.retry')));
      // One frame for the rebuild, then past the 200 ms cross-fade.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('suggest.placeholder.0')), findsOneWidget);
      expect(find.text('Tinolang manok + 1 cup rice'), findsNothing);
      repo.suggestionsHold!.complete();
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load suggestions."), findsNothing);
      expect(find.byKey(const Key('suggest.row.0')), findsOneWidget);
    });
  });
}
