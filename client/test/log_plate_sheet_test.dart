import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_plate_sheet.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'helpers/meal_suggestion_fixtures.dart';
import 'nutrition_controller_test.dart' show FakeNutritionRepository, emptyDay;

class _Profile extends ProfileNotifier {
  _Profile({this.fail = false});
  final bool fail;
  final patches = <Map<String, dynamic>>[];

  @override
  Future<Profile> build() async => const Profile(
    userId: 1, email: 'juan@example.com', fullName: 'Juan', onboardingCompleted: true,
    isPremium: false, notificationsEnabled: true, equipment: [], injuries: [],
  );

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    patches.add(fields);
    if (fail) throw StateError('offline');
  }
}

class _Logged {
  final calls = <(int, bool)>[];
}

Future<(FakeNutritionRepository, _Profile, _Logged)> _open(
  WidgetTester tester, {
  required Map<String, dynamic> plate,
  double usual = 1,
  bool riceFood = true,
  _Profile? profile,
}) async {
  final repo = FakeNutritionRepository()..days[fixtureToday] = emptyDay(fixtureToday);
  final p = profile ?? _Profile();
  final logged = _Logged();
  final answer = suggestionsAnswer('fits', [plate], share: {'kcal': 650, 'proteinG': 40}, riceCups: usual, riceFood: riceFood);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
      profileProvider.overrideWith(() => p),
    ],
    child: MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLogPlateSheet(
              context,
              plate: answer.suggestions.single,
              meal: 'lunch',
              date: fixtureToday,
              riceFood: answer.riceFood,
              usualRiceCups: answer.riceCups,
              onLogged: (entries, {required whileOpen}) => logged.calls.add((entries.length, whileOpen)),
              onFailedAfterClose: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (repo, p, logged);
}

String _total(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(const Key('logPlate.total')), matching: find.byType(Text)))
    .map((t) => t.data)
    .join(' | ');

/// The rice item line's texts (White rice is food 1), joined.
String _riceLine(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(const Key('logPlate.item.1')), matching: find.byType(Text)))
    .map((t) => t.data)
    .join(' | ');

void main() {
  testWidgets('a dish served with rice offers None to 2 cups, starting at the plate\'s own', (tester) async {
    await _open(tester, plate: plateJson(tinolaJson, cups: 1.5), usual: 1.5);
    expect(find.text('Rice'), findsOneWidget);
    for (final (cups, label) in [(0.0, 'None'), (0.5, '½ cup'), (1.0, '1 cup'), (1.5, '1½ cups'), (2.0, '2 cups')]) {
      expect(find.descendant(of: find.byKey(Key('logPlate.rice.$cups')), matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(_riceLine(tester), contains('1½ cups'), reason: 'the rice line says the amount, not one cup');
    expect(tester.widget<FsChip>(find.byKey(const Key('logPlate.rice.1.5'))).selected, isTrue);
    expect(find.byKey(const Key('logPlate.rice.note')), findsNothing, reason: 'the usual: nothing to say');
  });

  testWidgets('no rice row for a dish not served with rice, or with no White rice', (tester) async {
    await _open(tester, plate: plateJson(eggJson, rice: false));
    expect(find.text('Rice'), findsNothing);
  });

  testWidgets('no rice row when the server has no White rice to offer', (tester) async {
    await _open(tester, plate: plateJson(tinolaJson, rice: false, servedWithRice: false), riceFood: false);
    expect(find.text('Rice'), findsNothing);
  });

  testWidgets('a choice changes the rice line and the total at once, and says "from now on"', (tester) async {
    await _open(tester, plate: plateJson(tinolaJson));
    expect(_total(tester), contains('466 kcal'));
    await tester.tap(find.byKey(const Key('logPlate.rice.2.0')));
    await tester.pump();
    expect(_total(tester), contains('672 kcal')); // 260 + 2 × 206
    expect(_riceLine(tester), allOf(contains('2 cups'), contains('412 kcal')));
    expect(_riceLine(tester), isNot(contains('1 cup (160 g)')));
    expect(find.text('Plates will use 2 cups from now on.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logPlate.rice.0.0')));
    await tester.pump();
    expect(_total(tester), contains('260 kcal'));
    expect(find.byKey(const Key('logPlate.item.1')), findsNothing, reason: 'no rice line');
    expect(find.text('Plates will come without rice from now on.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logPlate.rice.1.0')));
    await tester.pump();
    expect(find.byKey(const Key('logPlate.rice.note')), findsNothing, reason: 'back to the usual');
  });

  testWidgets('a plate sent without its rice starts at None, says nothing until a choice, and can take rice', (tester) async {
    await _open(tester, plate: plateJson(tinolaJson, rice: false, servedWithRice: true), usual: 1.5);
    expect(tester.widget<FsChip>(find.byKey(const Key('logPlate.rice.0.0'))).selected, isTrue);
    expect(find.byKey(const Key('logPlate.rice.note')), findsNothing, reason: 'the server chose None, not the user');
    await tester.tap(find.byKey(const Key('logPlate.rice.2.0')));
    await tester.pump();
    expect(find.text('Plates will use 2 cups from now on.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logPlate.rice.0.0')));
    await tester.pump();
    expect(find.text('Plates will come without rice from now on.'), findsOneWidget, reason: 'None, chosen');
  });

  testWidgets('an untouched plate sent without its rice logs the dish alone and remembers nothing', (tester) async {
    final (repo, profile, logged) = await _open(
      tester,
      plate: plateJson(tinolaJson, rice: false, servedWithRice: true),
      usual: 1.5,
    );
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('log ')), ['log $fixtureToday lunch Tinolang manok x1.0']);
    expect(logged.calls, [(1, true)]);
    expect(profile.patches, isEmpty, reason: 'the usual stays 1½ cups');
  });

  testWidgets('a rice chip answers a tap 7 dp above or below its row', (tester) async {
    await _open(tester, plate: plateJson(tinolaJson));
    final first = tester.getRect(find.byKey(const Key('logPlate.rice.0.0')));
    await tester.tapAt(first.topCenter - const Offset(0, 7));
    await tester.pump();
    expect(tester.widget<FsChip>(find.byKey(const Key('logPlate.rice.0.0'))).selected, isTrue, reason: 'above');
    // With the note now showing under the row, which must not take the tap.
    expect(find.byKey(const Key('logPlate.rice.note')), findsOneWidget);
    final last = tester.getRect(find.byKey(const Key('logPlate.rice.2.0')));
    await tester.tapAt(last.bottomCenter + const Offset(0, 7));
    await tester.pump();
    expect(tester.widget<FsChip>(find.byKey(const Key('logPlate.rice.2.0'))).selected, isTrue, reason: 'below');
  });

  testWidgets('Log plate saves the rice at the chosen cups and remembers a changed amount', (tester) async {
    final (repo, profile, logged) = await _open(tester, plate: plateJson(tinolaJson));
    await tester.tap(find.byKey(const Key('logPlate.rice.1.5')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('log ')), [
      'log $fixtureToday lunch Tinolang manok x1.0',
      'log $fixtureToday lunch White rice x1.5',
    ]);
    expect(profile.patches, [{'usualRiceCups': 1.5}]);
    expect(logged.calls, [(2, true)]);
    expect(find.text('Rice'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('None logs the dish alone and remembers no rice', (tester) async {
    final (repo, profile, logged) = await _open(tester, plate: plateJson(tinolaJson));
    await tester.tap(find.byKey(const Key('logPlate.rice.0.0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('log ')), ['log $fixtureToday lunch Tinolang manok x1.0']);
    expect(profile.patches, [{'usualRiceCups': 0.0}]);
    expect(logged.calls, [(1, true)]);
  });

  testWidgets('the usual amount, unchanged, is not saved again', (tester) async {
    final (_, profile, _) = await _open(tester, plate: plateJson(tinolaJson));
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(profile.patches, isEmpty);
  });

  testWidgets('remembering failing leaves the plate logged and says nothing', (tester) async {
    final (_, _, logged) = await _open(tester, plate: plateJson(tinolaJson), profile: _Profile(fail: true));
    await tester.tap(find.byKey(const Key('logPlate.rice.2.0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(logged.calls, [(2, true)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the rice choice locks once Log plate is tapped', (tester) async {
    await _open(tester, plate: plateJson(tinolaJson));
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pump();
    // Still on screen (saving, or sliding away): every choice is inert.
    for (final cups in [0.0, 0.5, 1.0, 1.5, 2.0]) {
      expect(tester.widget<FsChip>(find.byKey(Key('logPlate.rice.$cups'))).onTap, isNull, reason: '$cups');
    }
    await tester.pumpAndSettle();
  });

  double chipsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(const Key('logPlate.rice.1.0')), matching: find.byType(AnimatedOpacity)).first)
      .opacity;

  testWidgets('the locked rice chips fade like a disabled control while saving and after a failed save', (tester) async {
    final (repo, _, _) = await _open(tester, plate: plateJson(tinolaJson));
    expect(chipsOpacity(tester), 1);
    final hold = repo.hold = Completer<void>();
    repo.failNext = true;
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pump();
    expect(chipsOpacity(tester), fsDisabledOpacity, reason: 'held');
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LogPlateSheet), findsOneWidget, reason: 'a failed save keeps the sheet open');
    expect(chipsOpacity(tester), fsDisabledOpacity, reason: 'failed');
  });

  testWidgets('an older server\'s answer (no riceCups, riceFood or servedWithRice) logs the dish and one cup', (tester) async {
    final repo = FakeNutritionRepository()..days[fixtureToday] = emptyDay(fixtureToday);
    final old = MealSuggestions.fromJson({
      'date': fixtureToday, 'meal': 'lunch', 'state': 'fits', 'share': {'kcal': 650, 'proteinG': 40},
      'suggestions': [
        {'food': tinolaJson, 'rice': riceJson, 'total': {'kcal': 466, 'proteinG': 29, 'carbsG': 53, 'fatG': 14}, 'highProtein': false},
      ],
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nutritionRepositoryProvider.overrideWithValue(repo),
        nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
        profileProvider.overrideWith(_Profile.new),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLogPlateSheet(
                context,
                plate: old.suggestions.single,
                meal: 'lunch',
                date: fixtureToday,
                riceFood: old.riceFood,
                usualRiceCups: old.riceCups,
                onLogged: (_, {required whileOpen}) {},
                onFailedAfterClose: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Rice'), findsNothing, reason: 'no choice without riceFood');
    expect(_total(tester), contains('466 kcal'));
    await tester.tap(find.byKey(const Key('logPlate.log')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('log ')), [
      'log $fixtureToday lunch Tinolang manok x1.0',
      'log $fixtureToday lunch White rice x1.0',
    ]);
  });
}
