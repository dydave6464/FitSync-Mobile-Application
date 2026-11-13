import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/ads/data/ad_source.dart';
import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/snap_meal.dart';
import 'package:fitsync/features/nutrition/presentation/nutrition_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_plate_sheet.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/meal_suggestions_section.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'helpers/fake_ad_source.dart';
import 'nutrition_controller_test.dart' show FakeNutritionRepository, emptyDay;

const _today = '2026-10-14';

/// A free trainee's profile: the ad slot at the foot of the tab asks it.
class _FreeProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => const Profile(
    userId: 1, email: 'juan@example.com', fullName: 'Juan Dela Cruz', onboardingCompleted: true,
    isPremium: false, notificationsEnabled: true, equipment: [], injuries: [],
  );
}

/// Refuses the plate's rice once, as a dropped connection would after the
/// dish went through.
class _RiceFailsOnce extends FakeNutritionRepository {
  bool _failed = false;

  @override
  Future<FoodEntry> logEntry({
    required String date,
    required String mealType,
    required double servings,
    required Food food,
    String? clientId,
  }) async {
    if (food.name == 'White rice' && !_failed) {
      _failed = true;
      clientIds.add(clientId);
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
    return super.logEntry(date: date, mealType: mealType, servings: servings, food: food, clientId: clientId);
  }
}

/// Holds each log until [logHold] completes, so a test can act while the
/// sheet saves. With [refuseRice], the rice is then refused.
class _HeldLog extends FakeNutritionRepository {
  Completer<void>? logHold;
  bool refuseRice = false;

  @override
  Future<FoodEntry> logEntry({
    required String date,
    required String mealType,
    required double servings,
    required Food food,
    String? clientId,
  }) async {
    if (logHold != null) await logHold!.future;
    if (refuseRice && food.name == 'White rice') {
      calls.add('log $date $mealType ${food.name} x$servings');
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
    return super.logEntry(date: date, mealType: mealType, servings: servings, food: food, clientId: clientId);
  }
}

Map<String, dynamic> _food(int id, String name, String serving, int kcal, num proteinG, num carbsG, num fatG) => {
  'foodId': id, 'name': name, 'servingDesc': serving, 'kcal': kcal, 'proteinG': proteinG, 'carbsG': carbsG, 'fatG': fatG,
};

final _rice = _food(1, 'White rice', '1 cup (160 g)', 206, 3, 45, 0);

/// A plate as the server sends it: the dish, its rice, and the two added up.
Map<String, dynamic> _plate(Map<String, dynamic> food, {bool rice = true, bool high = false}) {
  final items = [food, if (rice) _rice];
  num sum(String key) => items.fold<num>(0, (total, f) => total + (f[key] as num));
  return {
    'food': food,
    'rice': rice ? _rice : null,
    'total': {'kcal': sum('kcal'), 'proteinG': sum('proteinG'), 'carbsG': sum('carbsG'), 'fatG': sum('fatG')},
    'highProtein': high,
  };
}

// The spec's own three (section 2).
final _tinola = _plate(_food(10, 'Tinolang manok', '1 bowl (350 g)', 260, 26, 8, 14));
final _sinigang = _plate(
  _food(11, 'Sinigang na bangus (milkfish sour soup)', '1 bowl with broth (350 g)', 195, 23, 9, 7),
);
final _bangus = _plate(_food(12, 'Grilled bangus', '1 piece (150 g)', 206, 35, 0, 7), high: true);
final _egg = _plate(_food(13, 'Hard-boiled egg', '1 large', 78, 6.3, 0.6, 5.3), rice: false, high: true);

MealSuggestions _answer(String state, List<Map<String, dynamic>> plates, {Map<String, dynamic>? share}) =>
    MealSuggestions.fromJson({'date': _today, 'meal': 'lunch', 'state': state, 'share': share, 'suggestions': plates});

final _fits = _answer('fits', [_tinola, _sinigang, _bangus], share: {'kcal': 650, 'proteinG': 40});

/// The Nutrition tab at noon in Manila (lunch), today empty, with [lunch]
/// as the server's suggestions for lunch.
Future<FakeNutritionRepository> _pump(
  WidgetTester tester, {
  FakeNutritionRepository? repo,
  MealSuggestions? lunch,
  Size size = const Size(390, 1400),
  double textScale = 1,
  bool dark = false,
  bool reduceMotion = false,
}) async {
  final r = repo ?? FakeNutritionRepository();
  r.days[_today] = emptyDay(_today);
  if (lunch != null) r.suggestionsByMeal['lunch'] = lunch;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(r),
      // 12:00 in Manila: lunch.
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
      profileProvider.overrideWith(_FreeProfile.new),
      adSourceProvider.overrideWithValue(FakeAdSource()),
    ],
    child: MaterialApp(
      theme: dark ? fsDarkTheme() : fsLightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: const NutritionScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return r;
}

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
  testWidgets('fits: the plates for the meal the clock suggests, with what is left', (tester) async {
    await _pump(tester, lunch: _fits);
    for (final text in [
      'Suggested for lunch',
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

  testWidgets('sits under Snap a meal and above the meals, spaced 16, 4, 10 and 8', (tester) async {
    await _pump(tester, lunch: _fits);
    Rect r(Finder f) => tester.getRect(f);
    final heading = r(find.byKey(const Key('suggest.heading')));
    final sub = r(find.byKey(const Key('suggest.subheading')));
    final first = r(find.byKey(const Key('suggest.row.0')));
    final second = r(find.byKey(const Key('suggest.row.1')));
    expect(heading.top - r(find.byType(SnapMealCard)).bottom, closeTo(16, 0.01));
    expect(sub.top - heading.bottom, closeTo(4, 0.01));
    expect(first.top - sub.bottom, closeTo(10, 0.01));
    expect(second.top - first.bottom, closeTo(8, 0.01));
    expect(r(find.byKey(const Key('meal.add.breakfast'))).top, greaterThan(r(find.byKey(const Key('suggest.section'))).bottom));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(find.byKey(Key('suggest.row.$i'))).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets("the protein figure is in the Protein bar's green, with its number", (tester) async {
    await _pump(tester, lunch: _fits);
    final meta = find.byKey(const Key('suggest.meta.0'));
    final protein = (tester.widget<Text>(meta).textSpan! as TextSpan).children!.last as TextSpan;
    expect(protein.text, '29 g protein');
    expect(protein.style!.color, tester.element(meta).fs.accentText);
  });

  testWidgets('no target: says how to fit them to the day', (tester) async {
    await _pump(tester, lunch: _answer('no_target', [_tinola]));
    expect(find.text('Add your weight and height in Profile to fit these to your day.'), findsOneWidget);
    expect(find.text('Tinolang manok + 1 cup rice'), findsOneWidget);
  });

  testWidgets("today's calories reached: light options, without rice", (tester) async {
    await _pump(tester, lunch: _answer('reached', [_egg]));
    expect(find.text("You've reached today's calories. Light options:"), findsOneWidget);
    expect(find.text('Hard-boiled egg'), findsOneWidget);
    expect(find.text('1 large · 78 kcal · 6 g protein'), findsOneWidget);
  });

  testWidgets('nothing to suggest: no section at all', (tester) async {
    await _pump(tester);
    expect(find.text('Suggested for lunch'), findsNothing);
    expect(find.byKey(const Key('suggest.section')), findsNothing);
  });

  testWidgets('another day has no suggestions', (tester) async {
    await _pump(tester, lunch: _fits);
    await tester.tap(find.byKey(const Key('day.prev')));
    await tester.pumpAndSettle();
    expect(find.text('Suggested for lunch'), findsNothing);
  });

  testWidgets('while loading, three placeholders hold the space and say so', (tester) async {
    final semantics = tester.ensureSemantics();
    final repo = FakeNutritionRepository()..suggestionsHold = Completer<void>();
    await _pump(tester, repo: repo, lunch: _fits);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(Key('suggest.placeholder.$i')), findsOneWidget);
    }
    expect(find.bySemanticsLabel('Loading suggestions'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('suggest.section')), matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );
    repo.suggestionsHold!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest.placeholder.0')), findsNothing);
    expect(find.text('Tinolang manok + 1 cup rice'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a failed load is one line with Retry; the rest of the tab stays', (tester) async {
    final repo = FakeNutritionRepository()..failSuggestions = true;
    await _pump(tester, repo: repo, lunch: _fits);
    expect(find.text("Couldn't load suggestions."), findsOneWidget);
    expect(find.text('Add breakfast'), findsOneWidget);
    repo.failSuggestions = false;
    await tester.tap(find.byKey(const Key('suggest.retry')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load suggestions."), findsNothing);
    expect(find.text('Tinolang manok + 1 cup rice'), findsOneWidget);
  });

  testWidgets('Retry shows the placeholders while it asks again', (tester) async {
    final repo = FakeNutritionRepository()..failSuggestions = true;
    await _pump(tester, repo: repo, lunch: _fits);
    expect(find.text("Couldn't load suggestions."), findsOneWidget);
    repo
      ..failSuggestions = false
      ..suggestionsHold = Completer<void>();
    await tester.tap(find.byKey(const Key('suggest.retry')));
    // One frame for the rebuild, then past the 200 ms cross-fade.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('suggest.placeholder.0')), findsOneWidget);
    expect(find.text("Couldn't load suggestions."), findsNothing);
    repo.suggestionsHold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tinolang manok + 1 cup rice'), findsOneWidget);
  });

  testWidgets('a failed refetch after Log plate shows the error line, not the old rows', (tester) async {
    final repo = await _pump(tester, lunch: _fits);
    await tester.tap(find.byKey(const Key('suggest.row.0')));
    await tester.pumpAndSettle();
    // UNKNOWN_ERROR: never retried, so the refetch fails at once.
    repo.failSuggestions = true;
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load suggestions."), findsOneWidget);
    expect(find.text('Tinolang manok + 1 cup rice'), findsNothing);
    expect(find.text('Logged to lunch'), findsOneWidget);

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

  testWidgets('each row is one button saying the plate, with a Log hint', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, lunch: _fits);
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

  testWidgets('tapping a row opens Log to Lunch: each item, the plate total and Log plate', (tester) async {
    await _pump(tester, lunch: _fits);
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
    final adobo = _plate(_food(14, 'Adobong manok', '1 serving (150 g)', 260, 26.3, 8, 14));
    await _pump(tester, lunch: _answer('fits', [adobo], share: {'kcal': 650, 'proteinG': 40}));
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

  testWidgets('Log plate logs the dish and its rice, each with its own key, then offers Undo', (tester) async {
    final repo = await _pump(tester, lunch: _fits);
    final asked = repo.suggestionCalls.length;
    await tester.tap(find.byKey(const Key('suggest.row.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();

    expect(
      repo.calls,
      containsAllInOrder(['log $_today lunch Tinolang manok x1.0', 'log $_today lunch White rice x1.0']),
    );
    expect(repo.clientIds, hasLength(2));
    expect(repo.clientIds.every((id) => id != null), isTrue);
    expect(repo.clientIds.toSet(), hasLength(2));
    expect(find.byType(LogPlateSheet), findsNothing);
    expect(find.text('Logged to lunch'), findsOneWidget);
    // The day changed, so the suggestions are asked for again.
    expect(repo.suggestionCalls.length, greaterThan(asked));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.calls, containsAll(['delete 100', 'delete 101']));
    expect(repo.dayOf(_today).entries, isEmpty);
  });

  testWidgets('a failed log stays in the sheet with Retry, which sends the same keys', (tester) async {
    final repo = _RiceFailsOnce();
    await _pump(tester, repo: repo, lunch: _fits);
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
    expect(repo.dayOf(_today).entries.where((e) => e.name == 'Tinolang manok'), hasLength(1));
    expect(repo.dayOf(_today).entries.where((e) => e.name == 'White rice'), hasLength(1));
  });

  testWidgets('dragged away mid-save, the plate still says Logged with Undo', (tester) async {
    final repo = _HeldLog();
    await _pump(tester, repo: repo, lunch: _fits);
    await tester.tap(find.byKey(const Key('suggest.row.0')));
    await tester.pumpAndSettle();
    repo.logHold = Completer<void>();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    // Not pumpAndSettle: the button's spinner keeps animating.
    await tester.pump();
    await tester.drag(find.byKey(const Key('sheet.handle')), const Offset(0, 600));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LogPlateSheet), findsNothing);

    repo.logHold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Logged to lunch'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(
      repo.calls,
      containsAllInOrder(['log $_today lunch Tinolang manok x1.0', 'log $_today lunch White rice x1.0']),
    );
  });

  testWidgets('dragged away mid-save, a refused rice still says so', (tester) async {
    final repo = _HeldLog();
    await _pump(tester, repo: repo, lunch: _fits);
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
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.textContaining("Couldn't log the plate.")),
      findsOneWidget,
    );
    expect(find.text('Logged to lunch'), findsNothing);
  });

  // The sheet stays mounted for its exit animation after a drag, while its
  // route is already popping: a save landing then must not pop the screen
  // under it.
  testWidgets('a save landing while the dragged sheet slides away keeps the Nutrition screen', (tester) async {
    final repo = _HeldLog();
    await _pump(tester, repo: repo, lunch: _fits);
    await tester.tap(find.byKey(const Key('suggest.row.0')));
    await tester.pumpAndSettle();
    repo.logHold = Completer<void>();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pump();
    await _dragHalfAway(tester);
    expect(find.byType(LogPlateSheet), findsOneWidget, reason: 'still sliding away');

    repo.logHold!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NutritionScreen), findsOneWidget);
    expect(find.byType(LogPlateSheet), findsNothing);
    expect(find.text('Logged to lunch'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('a refused rice landing while the dragged sheet slides away still says so', (tester) async {
    final repo = _HeldLog();
    await _pump(tester, repo: repo, lunch: _fits);
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
    expect(find.byType(NutritionScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.textContaining("Couldn't log the plate.")),
      findsOneWidget,
    );
    expect(find.text('Logged to lunch'), findsNothing);
  });

  testWidgets('the rows cross-fade over 200 ms', (tester) async {
    await _pump(tester, lunch: _fits);
    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(of: find.byKey(const Key('suggest.section')), matching: find.byType(AnimatedSwitcher)),
    );
    expect(switcher.duration, const Duration(milliseconds: 200));
  });

  testWidgets('with reduced motion the rows switch at once', (tester) async {
    await _pump(tester, lunch: _fits, reduceMotion: true);
    expect(
      find.descendant(of: find.byKey(const Key('suggest.section')), matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );
  });

  group('while the tab loads a day', () {
    /// The section alone, [enabled] or not, its rows already loaded.
    Future<void> pumpSection(WidgetTester tester, {required bool enabled, bool reduceMotion = false}) async {
      final r = FakeNutritionRepository()..suggestionsByMeal['lunch'] = _fits;
      await tester.pumpWidget(ProviderScope(
        overrides: [nutritionRepositoryProvider.overrideWithValue(r)],
        child: MaterialApp(
          theme: fsLightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(children: [MealSuggestionsSection(meal: 'lunch', enabled: enabled)]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    AnimatedOpacity fade(WidgetTester tester, int i) => tester.widget<AnimatedOpacity>(
      find.descendant(of: find.byKey(Key('suggest.row.$i')), matching: find.byType(AnimatedOpacity)),
    );

    testWidgets('the rows fade to the disabled 0.45, over 150 ms', (tester) async {
      await pumpSection(tester, enabled: false);
      for (var i = 0; i < 3; i++) {
        expect(fade(tester, i).opacity, 0.45);
        expect(fade(tester, i).duration, const Duration(milliseconds: 150));
      }
    });

    testWidgets('enabled, the rows are whole', (tester) async {
      await pumpSection(tester, enabled: true);
      for (var i = 0; i < 3; i++) {
        expect(fade(tester, i).opacity, 1.0);
      }
    });

    testWidgets('with reduced motion the rows fade at once', (tester) async {
      await pumpSection(tester, enabled: false, reduceMotion: true);
      expect(fade(tester, 0).opacity, 0.45);
      expect(fade(tester, 0).duration, Duration.zero);
    });
  });

  for (final dark in [false, true]) {
    testWidgets('fits a 320 dp phone at 2x text (${dark ? 'dark' : 'light'})', (tester) async {
      final long = _plate(
        _food(20, 'Ginataang tulingan (frigate tuna in coconut milk)', '1 fish piece with sauce (210 g)', 293, 26.3,
            7.5, 17.9),
        high: true,
      );
      await _pump(
        tester,
        lunch: _answer('fits', [long, _tinola, _bangus], share: {'kcal': 1150, 'proteinG': 47.5}),
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
}
