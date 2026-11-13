import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/settings/presentation/meal_preferences_screen.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

/// A profile whose writes land as the real one's do: a saved patch becomes
/// the profile on screen. [patches] records each saved write; [gate] holds
/// every write until completed; [error] or [fail] refuse it.
class _Profile extends ProfileNotifier {
  _Profile({
    this.rice = 1,
    this.avoid = const [],
    this.fail = false,
    this.error,
    this.gate,
  });

  double rice;
  List<String> avoid;
  final bool fail;
  final Object? error;
  final Completer<void>? gate;
  final patches = <Map<String, dynamic>>[];
  int patchCalls = 0;

  Profile _now() => Profile(
    userId: 1,
    email: 'juan@example.com',
    fullName: 'Juan',
    onboardingCompleted: true,
    isPremium: false,
    notificationsEnabled: true,
    equipment: const [],
    injuries: const [],
    usualRiceCups: rice,
    avoidFoods: avoid,
  );

  @override
  Future<Profile> build() async => _now();

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    patchCalls += 1;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    if (fail) {
      throw const ApiException('PROFILE_INVALID', 'That could not be saved.');
    }
    patches.add(fields);
    if (fields['usualRiceCups'] case final double cups) rice = cups;
    if (fields['avoidFoods'] case final List<String> groups) avoid = groups;
    state = AsyncData(_now());
  }
}

final _tinola = HiddenSuggestion(
  foodId: 10,
  name: 'Tinolang manok',
  hiddenAt: DateTime.utc(2026, 11, 13, 9),
);
final _sinigang = HiddenSuggestion(
  foodId: 13,
  name: 'Sinigang na hipon',
  hiddenAt: DateTime.utc(2026, 11, 12, 9),
);

/// Opens the screen from a page under it, as Settings and Meal ideas do.
Future<(_Profile, FakeNutritionRepository)> _pump(
  WidgetTester tester, {
  _Profile? profile,
  FakeNutritionRepository? repo,
  Size size = const Size(390, 1400),
  double textScale = 1,
  bool dark = false,
}) async {
  final p = profile ?? _Profile();
  final r = repo ?? FakeNutritionRepository();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(() => p),
        nutritionRepositoryProvider.overrideWithValue(r),
      ],
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MealPreferencesScreen(),
                ),
              ),
              child: const Text('home'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('home'));
  await tester.pumpAndSettle();
  return (p, r);
}

FsChip _chip(WidgetTester tester, String key) =>
    tester.widget<FsChip>(find.byKey(Key(key)));

List<String> _avoided(WidgetTester tester) => [
  for (final g in foodGroups)
    if (_chip(tester, 'prefs.avoid.$g').selected) g,
];

void main() {
  testWidgets('a page titled Meal preferences with three headings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Meal preferences'),
      ),
      findsOneWidget,
    );
    final headings = ['RICE WITH MEALS', 'FOODS I AVOID', 'DISHES YOU HID'];
    for (final h in headings) {
      expect(
        tester.getSemantics(find.text(h)),
        isSemantics(label: h, isHeader: true),
      );
    }
    final tops = [for (final h in headings) tester.getTopLeft(find.text(h)).dy];
    expect(tops, orderedEquals([...tops]..sort()), reason: 'in that order');
    semantics.dispose();
  });

  group('Rice with meals', () {
    testWidgets('the usual amount is the chip picked', (tester) async {
      await _pump(tester, profile: _Profile(rice: 1.5));
      expect(
        [for (final c in riceChoices) _chip(tester, 'prefs.rice.$c').selected],
        [false, false, false, true, false],
      );
      expect(
        find.text(
          'Used for suggested plates. You can change it when you log a plate.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no rice is None', (tester) async {
      await _pump(tester, profile: _Profile(rice: 0));
      expect(_chip(tester, 'prefs.rice.0.0').label, 'None');
      expect(_chip(tester, 'prefs.rice.0.0').selected, isTrue);
      expect(_chip(tester, 'prefs.rice.1.5').label, '1½ cups');
    });

    testWidgets('a tap saves the new amount at once', (tester) async {
      final (profile, _) = await _pump(tester);
      await tester.tap(find.byKey(const Key('prefs.rice.2.0')));
      await tester.pumpAndSettle();
      expect(profile.patches, [
        {'usualRiceCups': 2.0},
      ]);
      expect(_chip(tester, 'prefs.rice.2.0').selected, isTrue);
    });

    testWidgets('a failed save says so in place and keeps the old amount', (
      tester,
    ) async {
      await _pump(tester, profile: _Profile(fail: true));
      await tester.tap(find.byKey(const Key('prefs.rice.0.5')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('prefs.riceError')),
          matching: find.text("Couldn't save your rice. Try again."),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(_chip(tester, 'prefs.rice.1.0').selected, isTrue);
      expect(_chip(tester, 'prefs.rice.0.5').selected, isFalse);
    });

    testWidgets('a save that fails after the screen closed says so on the '
        'page under it', (tester) async {
      final gate = Completer<void>();
      await _pump(
        tester,
        profile: _Profile(
          gate: gate,
          error: const ApiException('NETWORK_ERROR', 'SocketException'),
        ),
      );
      await tester.tap(find.byKey(const Key('prefs.rice.2.0')));
      await tester.pump();
      // Closed while the save is still on its way.
      Navigator.of(tester.element(find.byKey(const Key('prefs.rice.2.0'))))
          .pop();
      await tester.pumpAndSettle();
      expect(find.byType(MealPreferencesScreen), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text("Couldn't save your rice. Try again."),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a tap just below the chips still picks one', (tester) async {
      final (profile, _) = await _pump(tester);
      // The chips are drawn about 32 dp tall; their 48 dp band reaches 8 dp
      // past the row, below as well as above.
      final chip = tester.getRect(find.byKey(const Key('prefs.rice.2.0')));
      await tester.tapAt(chip.bottomCenter + const Offset(0, 4));
      await tester.pumpAndSettle();
      expect(profile.patches, [
        {'usualRiceCups': 2.0},
      ]);
    });

    testWidgets('a tap just above the first row still picks one', (
      tester,
    ) async {
      final (profile, _) = await _pump(tester);
      // The room above the first row is inside the section, not in the
      // heading above it, so the chip's band can reach it.
      final chip = tester.getRect(find.byKey(const Key('prefs.rice.0.0')));
      await tester.tapAt(chip.topCenter - const Offset(0, 4));
      await tester.pumpAndSettle();
      expect(profile.patches, [
        {'usualRiceCups': 0.0},
      ]);
    });

    for (final size in const [Size(360, 640), Size(640, 360), Size(844, 390)]) {
      testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} '
          'phone at 2x text, the error line too', (tester) async {
        await _pump(
          tester,
          profile: _Profile(fail: true),
          size: size,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('prefs.rice.0.5')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('prefs.rice.0.5')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('prefs.riceError')), findsOneWidget);
      });
    }
  });

  group('Foods I avoid', () {
    testWidgets('six chips with their labels, each a toggle; the two lines '
        'under them', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, profile: _Profile(avoid: ['beef']));
      expect(
        [for (final g in foodGroups) _chip(tester, 'prefs.avoid.$g').label],
        ['Pork', 'Beef', 'Chicken', 'Fish', 'Shrimp & shellfish', 'Egg'],
      );
      for (final g in foodGroups) {
        final chip = _chip(tester, 'prefs.avoid.$g');
        expect(chip.toggle, isTrue);
        expect(chip.exclusive, isFalse);
      }
      expect(
        tester.getSemantics(find.byKey(const Key('prefs.avoid.pork'))),
        isSemantics(
          label: 'Pork',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('prefs.avoid.beef'))),
        isSemantics(
          label: 'Beef',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      final under = [
        'Suggestions skip dishes often made with these.',
        'Recipes vary — check ingredients if you have an allergy.',
      ];
      final chipsBottom = tester
          .getRect(find.byKey(const Key('prefs.avoid.egg')))
          .bottom;
      for (final line in under) {
        expect(find.text(line), findsOneWidget);
        expect(tester.getTopLeft(find.text(line)).dy, greaterThan(chipsBottom));
      }
      semantics.dispose();
    });

    testWidgets('each tap saves the whole set, in the fixed order', (
      tester,
    ) async {
      final (profile, _) = await _pump(tester);
      await tester.tap(find.byKey(const Key('prefs.avoid.pork')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prefs.avoid.egg')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prefs.avoid.beef')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prefs.avoid.pork')));
      await tester.pumpAndSettle();
      expect(profile.patches, [
        {
          'avoidFoods': ['pork'],
        },
        {
          'avoidFoods': ['pork', 'egg'],
        },
        {
          'avoidFoods': ['pork', 'beef', 'egg'],
        },
        {
          'avoidFoods': ['beef', 'egg'],
        },
      ]);
      expect(_avoided(tester), ['beef', 'egg']);
    });

    testWidgets('a tap just above the first row still toggles one', (
      tester,
    ) async {
      final (profile, _) = await _pump(tester);
      // The room above the first row is inside the section, not in the
      // heading above it, so the chip's band can reach it.
      final pork = tester.getRect(find.byKey(const Key('prefs.avoid.pork')));
      await tester.tapAt(pork.topCenter - const Offset(0, 4));
      await tester.pumpAndSettle();
      expect(profile.patches, [
        {
          'avoidFoods': ['pork'],
        },
      ]);
    });

    testWidgets('while it saves, the new set shows and further taps wait', (
      tester,
    ) async {
      final gate = Completer<void>();
      final (profile, _) = await _pump(tester, profile: _Profile(gate: gate));
      await tester.tap(find.byKey(const Key('prefs.avoid.pork')));
      await tester.pump();
      expect(_avoided(tester), ['pork']);
      expect(_chip(tester, 'prefs.avoid.beef').onTap, isNull);
      await tester.tap(find.byKey(const Key('prefs.avoid.beef')));
      await tester.pump();
      expect(profile.patchCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(profile.patches, [
        {
          'avoidFoods': ['pork'],
        },
      ]);
      expect(_avoided(tester), ['pork']);
      expect(_chip(tester, 'prefs.avoid.beef').onTap, isNotNull);
    });

    testWidgets('a failed save puts the chips back and says so in place', (
      tester,
    ) async {
      await _pump(tester, profile: _Profile(avoid: ['beef'], fail: true));
      await tester.tap(find.byKey(const Key('prefs.avoid.pork')));
      await tester.pumpAndSettle();
      expect(_avoided(tester), ['beef']);
      expect(
        find.descendant(
          of: find.byKey(const Key('prefs.avoidError')),
          matching: find.text("Couldn't save. Try again."),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('Dishes you hid', () {
    testWidgets('lists them newest first, each with Show again', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repo = FakeNutritionRepository()
        ..hidden.addAll([_tinola, _sinigang]);
      await _pump(tester, repo: repo);
      final tinola = find.byKey(const Key('prefs.hidden.10'));
      final sinigang = find.byKey(const Key('prefs.hidden.13'));
      expect(
        find.descendant(of: tinola, matching: find.text('Tinolang manok')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sinigang, matching: find.text('Sinigang na hipon')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(tinola).dy,
        lessThan(tester.getTopLeft(sinigang).dy),
      );
      final show = find.byKey(const Key('prefs.show.10'));
      expect(
        find.descendant(of: show, matching: find.text('Show again')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(show),
        isSemantics(
          label: 'Show Tinolang manok again',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(show).height, greaterThanOrEqualTo(48));
      expect(find.byKey(const Key('prefs.hiddenEmpty')), findsNothing);
      semantics.dispose();
    });

    testWidgets('Show again shows the dish again and the row leaves', (
      tester,
    ) async {
      final repo = FakeNutritionRepository()
        ..hidden.addAll([_tinola, _sinigang]);
      await _pump(tester, repo: repo);
      final hold = repo.hiddenHold = Completer<void>();
      await tester.tap(find.byKey(const Key('prefs.show.10')));
      await tester.pump();
      // Busy meanwhile: no second tap.
      final show = find.byKey(const Key('prefs.show.10'));
      expect(tester.widget<TextButton>(show).onPressed, isNull);
      expect(
        find.descendant(
          of: show,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      hold.complete();
      repo.hiddenHold = null;
      await tester.pumpAndSettle();
      expect(repo.showCalls, [10]);
      expect(find.byKey(const Key('prefs.hidden.10')), findsNothing);
      expect(find.byKey(const Key('prefs.hidden.13')), findsOneWidget);
    });

    testWidgets('Show again failing says so under the row, which stays', (
      tester,
    ) async {
      final repo = FakeNutritionRepository()
        ..hidden.addAll([_tinola, _sinigang]);
      await _pump(tester, repo: repo);
      repo.failHidden = true;
      await tester.tap(find.byKey(const Key('prefs.show.10')));
      await tester.pumpAndSettle();
      expect(repo.showCalls, [10]);
      expect(find.byKey(const Key('prefs.hidden.10')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('prefs.hiddenError.10')),
          matching: find.text("Couldn't show Tinolang manok again. Try again."),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('prefs.show.10')))
            .onPressed,
        isNotNull,
        reason: 'it can be tried again',
      );
      expect(find.byKey(const Key('prefs.hiddenError.13')), findsNothing);
    });

    testWidgets('none hidden says how to hide one', (tester) async {
      await _pump(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('prefs.hiddenEmpty')),
          matching: find.text(
            'No hidden dishes. Use "Don\'t suggest this" on a plate to hide one.',
          ),
          matchRoot: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a list that will not load offers Try again, which loads it', (
      tester,
    ) async {
      final repo = FakeNutritionRepository()
        ..hidden.add(_tinola)
        ..failHidden = true;
      await _pump(tester, repo: repo);
      expect(find.byType(FsRetry), findsOneWidget);
      expect(
        find.text('Something went wrong on our side. Please try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('prefs.hidden.10')), findsNothing);
      repo.failHidden = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(FsRetry), findsNothing);
      expect(find.byKey(const Key('prefs.hidden.10')), findsOneWidget);
    });
  });

  for (final dark in [false, true]) {
    testWidgets('fits a 320 dp phone at 2x text: the chips wrap, nothing '
        'overflows (${dark ? 'dark' : 'light'})', (tester) async {
      final repo = FakeNutritionRepository()
        ..hidden.addAll([_tinola, _sinigang]);
      await _pump(
        tester,
        repo: repo,
        profile: _Profile(avoid: ['pork']),
        size: const Size(320, 2400),
        textScale: 2,
        dark: dark,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byKey(const Key('prefs.avoid.egg'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('prefs.avoid.pork'))).dy,
        ),
        reason: 'the chips take more than one line',
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('prefs.rice.2.0'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('prefs.rice.0.0'))).dy,
        ),
      );
      expect(find.text('Tinolang manok'), findsOneWidget);
      expect(find.text('Show again'), findsNWidgets(2));
      for (final g in foodGroups) {
        expect(find.text(foodGroupLabel(g)), findsOneWidget);
      }
    });
  }

  testWidgets('scrolled to the end, the list clears the bottom safe area', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    await _pump(tester, size: const Size(390, 500));
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('prefs.hiddenEmpty'))).bottom,
      lessThanOrEqualTo(500 - 34),
    );
  });
}
