import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/ads/data/ad_source.dart';
import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';
import 'package:fitsync/features/nutrition/presentation/meal_ideas_screen.dart';
import 'package:fitsync/features/nutrition/presentation/nutrition_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/meal_ideas_card.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/meal_section.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'helpers/fake_ad_source.dart';
import 'helpers/meal_suggestion_fixtures.dart';
import 'nutrition_controller_test.dart' show FakeNutritionRepository, emptyDay;

/// A free trainee's profile: the ad slot at the foot of the tab asks it.
class _FreeProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => const Profile(
    userId: 1, email: 'juan@example.com', fullName: 'Juan Dela Cruz', onboardingCompleted: true,
    isPremium: false, notificationsEnabled: true, equipment: [], injuries: [],
  );
}

final _fits = suggestionsAnswer(
  'fits',
  [plateJson(tinolaJson), plateJson(sinigangJson), plateJson(bangusJson, high: true)],
  share: {'kcal': 650, 'proteinG': 40},
);

/// The Nutrition tab at noon in Manila (lunch), today empty, with [lunch]
/// as the server's suggestions for lunch.
Future<FakeNutritionRepository> _pump(
  WidgetTester tester, {
  FakeNutritionRepository? repo,
  MealSuggestions? lunch,
  Size size = const Size(390, 1400),
  double textScale = 1,
  bool dark = false,
}) async {
  final r = repo ?? FakeNutritionRepository();
  r.days[fixtureToday] = emptyDay(fixtureToday);
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
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const NutritionScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return r;
}

void main() {
  testWidgets('fits: the top plate, its kcal, and how many more', (tester) async {
    await _pump(tester, lunch: _fits);
    expect(find.text('Suggested for lunch'), findsOneWidget);
    expect(find.text('Tinolang manok + 1 cup rice · 466 kcal'), findsOneWidget);
    expect(find.text('and 2 more that fit'), findsOneWidget);
    expect(find.byKey(const Key('suggest.row.0')), findsNothing, reason: 'the rows live on the page now');
  });

  testWidgets('one plate: no "more" line', (tester) async {
    await _pump(tester, lunch: suggestionsAnswer('fits', [plateJson(tinolaJson)], share: {'kcal': 650, 'proteinG': 40}));
    expect(find.byKey(const Key('ideas.card.line1')), findsOneWidget);
    expect(find.byKey(const Key('ideas.card.line2')), findsNothing);
  });

  testWidgets('no target: the top plate and how to fit them', (tester) async {
    await _pump(tester, lunch: suggestionsAnswer('no_target', [plateJson(tinolaJson)]));
    expect(find.text('Tinolang manok + 1 cup rice · 466 kcal'), findsOneWidget);
    expect(find.text('Add your weight and height to fit these to your day'), findsOneWidget);
  });

  testWidgets("reached: says so, with light options", (tester) async {
    await _pump(tester, lunch: suggestionsAnswer('reached', [plateJson(eggJson, rice: false)]));
    expect(find.text("You've reached today's calories"), findsOneWidget);
    expect(find.text('Light options'), findsOneWidget);
  });

  testWidgets('one button, said in full, opening meal ideas', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, lunch: _fits);
    expect(
      tester.getSemantics(find.byKey(const Key('ideas.card'))),
      matchesSemantics(
        label: 'Suggested for lunch: Tinolang manok with 1 cup rice, 466 kilocalories, and 2 more',
        hint: 'Opens meal ideas',
        isButton: true, isEnabled: true, hasEnabledState: true, hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('at least 48 dp tall', (tester) async {
    await _pump(tester, lunch: suggestionsAnswer('fits', [plateJson(tinolaJson)], share: {'kcal': 650, 'proteinG': 40}));
    expect(tester.getSize(find.byKey(const Key('ideas.card'))).height, greaterThanOrEqualTo(48));
  });

  for (final dark in [false, true]) {
    testWidgets('fits a 320 dp phone at 2x text, both lines shown (${dark ? 'dark' : 'light'})', (tester) async {
      final lunch = suggestionsAnswer('fits', [plateJson(sinigangJson, cups: 1.5), plateJson(tinolaJson, cups: 1.5)],
          share: {'kcal': 650, 'proteinG': 40}, riceCups: 1.5);
      await _pump(tester, lunch: lunch, size: const Size(320, 3000), textScale: 2, dark: dark);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('ideas.card'))).height, greaterThanOrEqualTo(48));
      expect(find.byKey(const Key('ideas.card.line1')), findsOneWidget);
      expect(find.byKey(const Key('ideas.card.line2')), findsOneWidget);
    });
  }

  testWidgets('sits 12 under Snap a meal and above the meals', (tester) async {
    await _pump(tester, lunch: _fits);
    final snap = tester.getBottomLeft(find.byKey(const Key('snap.card'))).dy;
    final card = tester.getRect(find.byKey(const Key('ideas.card')));
    expect(card.top - snap, 12);
    expect(tester.getTopLeft(find.byType(MealSection).first).dy, greaterThan(card.bottom));
  });

  testWidgets("tapping it opens Meal ideas on the clock's meal", (tester) async {
    await _pump(tester, lunch: _fits);
    await tester.tap(find.byKey(const Key('ideas.card')));
    await tester.pumpAndSettle();
    expect(find.byType(MealIdeasScreen), findsOneWidget);
    expect(tester.widget<FsChip>(find.byKey(const Key('ideas.meal.lunch'))).selected, isTrue);
  });

  testWidgets('a plate logged on the page: back on the tab with Logged and Undo, which removes both', (tester) async {
    final repo = await _pump(tester, lunch: _fits);
    await tester.tap(find.byKey(const Key('ideas.card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggest.row.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(find.byType(MealIdeasScreen), findsNothing);
    expect(find.byType(NutritionScreen), findsOneWidget);
    expect(find.text('Logged to lunch'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('delete ')), hasLength(2));
    expect(repo.dayOf(fixtureToday).entries, isEmpty);
  });

  testWidgets('nothing to suggest: no card at all', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('ideas.card')), findsNothing);
    expect(find.text('Suggested for lunch'), findsNothing);
    // No gap left behind: the meals sit 16 under Snap a meal, as before.
    final snap = tester.getBottomLeft(find.byKey(const Key('snap.card'))).dy;
    expect(tester.getTopLeft(find.byType(MealSection).first).dy - snap, closeTo(16, 0.01));
  });

  testWidgets('another day has no card', (tester) async {
    await _pump(tester, lunch: _fits);
    await tester.tap(find.byKey(const Key('day.prev')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ideas.card')), findsNothing);
    expect(find.text('Suggested for lunch'), findsNothing);
  });

  testWidgets('while loading, a card-shaped placeholder holds the space and says so', (tester) async {
    final semantics = tester.ensureSemantics();
    final repo = FakeNutritionRepository()..suggestionsHold = Completer<void>();
    // Wide enough that the test font keeps each line on one line.
    await _pump(tester, repo: repo, lunch: _fits, size: const Size(800, 1400));
    expect(find.byKey(const Key('ideas.card.loading')), findsOneWidget);
    expect(find.byKey(const Key('ideas.card.line1')), findsNothing);
    expect(find.bySemanticsLabel('Loading suggestions'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('ideas.card.loading')), matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );
    final placeholder = tester.getSize(find.byKey(const Key('ideas.card.loading'))).height;
    repo.suggestionsHold!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ideas.card.loading')), findsNothing);
    expect(find.text('Tinolang manok + 1 cup rice · 466 kcal'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('ideas.card'))).height, closeTo(placeholder, 0.01),
        reason: 'nothing jumps when the card comes');
    semantics.dispose();
  });

  testWidgets('a failed load is one line with Retry; the rest of the tab stays', (tester) async {
    final repo = FakeNutritionRepository()..failSuggestions = true;
    await _pump(tester, repo: repo, lunch: _fits);
    expect(find.text("Couldn't load suggestions."), findsOneWidget);
    expect(find.byKey(const Key('ideas.card')), findsNothing);
    expect(find.text('Add breakfast'), findsOneWidget);
    repo.failSuggestions = false;
    await tester.tap(find.byKey(const Key('suggest.retry')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load suggestions."), findsNothing);
    expect(find.text('Tinolang manok + 1 cup rice · 466 kcal'), findsOneWidget);
  });

  testWidgets('Retry shows the placeholder while it asks again', (tester) async {
    final repo = FakeNutritionRepository()..failSuggestions = true;
    await _pump(tester, repo: repo, lunch: _fits);
    expect(find.text("Couldn't load suggestions."), findsOneWidget);
    repo
      ..failSuggestions = false
      ..suggestionsHold = Completer<void>();
    await tester.tap(find.byKey(const Key('suggest.retry')));
    await tester.pump();
    expect(find.byKey(const Key('ideas.card.loading')), findsOneWidget);
    expect(find.text("Couldn't load suggestions."), findsNothing);
    repo.suggestionsHold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tinolang manok + 1 cup rice · 466 kcal'), findsOneWidget);
  });

  group('while the tab loads a day', () {
    /// The card alone, opening or not, its plates already loaded.
    Future<List<String>> pumpCard(WidgetTester tester, {required bool enabled, bool reduceMotion = false}) async {
      final opened = <String>[];
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
            body: ListView(children: [MealIdeasCard(meal: 'lunch', onOpen: enabled ? () => opened.add('lunch') : null)]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return opened;
    }

    AnimatedOpacity fade(WidgetTester tester) => tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.byKey(const Key('ideas.card')), matching: find.byType(AnimatedOpacity)).first,
    );

    testWidgets('the card fades to the disabled 0.45, over 150 ms, and a tap does nothing', (tester) async {
      final semantics = tester.ensureSemantics();
      final opened = await pumpCard(tester, enabled: false);
      expect(fade(tester).opacity, fsDisabledOpacity);
      expect(fade(tester).duration, const Duration(milliseconds: 150));
      expect(
        tester.getSemantics(find.byKey(const Key('ideas.card'))),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      await tester.tap(find.byKey(const Key('ideas.card')));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      semantics.dispose();
    });

    testWidgets('enabled, the card is whole and opens', (tester) async {
      final opened = await pumpCard(tester, enabled: true);
      expect(fade(tester).opacity, 1.0);
      await tester.tap(find.byKey(const Key('ideas.card')));
      await tester.pumpAndSettle();
      expect(opened, ['lunch']);
    });

    testWidgets('with reduced motion the card fades at once', (tester) async {
      await pumpCard(tester, enabled: false, reduceMotion: true);
      expect(fade(tester).opacity, fsDisabledOpacity);
      expect(fade(tester).duration, Duration.zero);
    });
  });

  group('the card in words', () {
    test('fits with one plate has no second line', () {
      final lines = ideasCardLines(suggestionsAnswer('fits', [plateJson(tinolaJson)], share: {'kcal': 650, 'proteinG': 40}));
      expect(lines.line1, 'Tinolang manok + 1 cup rice · 466 kcal');
      expect(lines.line2, isNull);
    });

    test('a plate without rice is the dish alone, said without rice', () {
      final d = suggestionsAnswer('fits', [plateJson(eggJson, rice: false), plateJson(tinolaJson)],
          share: {'kcal': 650, 'proteinG': 40});
      expect(ideasCardLines(d).line1, 'Hard-boiled egg · 78 kcal');
      expect(ideasCardSpoken(d), 'Suggested for lunch: Hard-boiled egg, 78 kilocalories, and 1 more');
    });

    test('no target and reached are said as written', () {
      expect(
        ideasCardSpoken(suggestionsAnswer('no_target', [plateJson(tinolaJson, cups: 1.5)])),
        'Suggested for lunch: Tinolang manok with 1 and a half cups rice, 569 kilocalories. '
        'Add your weight and height to fit these to your day',
      );
      expect(
        ideasCardSpoken(suggestionsAnswer('reached', [plateJson(eggJson, rice: false)])),
        "Suggested for lunch: You've reached today's calories. Light options",
      );
    });
  });
}
