import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/meal_ideas_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_plate_sheet.dart';
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
class _HeldLog extends FakeNutritionRepository {
  Completer<void>? logHold;

  @override
  Future<FoodEntry> logEntry({
    required String date, required String mealType, required double servings, required Food food, String? clientId,
  }) async {
    if (logHold != null) await logHold!.future;
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
      theme: fsLightTheme(),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.value = await Navigator.of(context).push<PlateLogged>(
              MaterialPageRoute(builder: (_) => MealIdeasScreen(initialMeal: initialMeal)),
            ),
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
}
