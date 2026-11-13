import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/dish_photo.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_plate_sheet.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'helpers/fake_dish_photos.dart';
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
  ValueChanged<SuggestedFood>? onHidden,
  bool fromPushedPage = false,
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
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
      home: Builder(
        builder: (context) {
          // The page the sheet opens over, as Meal ideas is.
          Widget page() => Scaffold(
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
                  onHidden: onHidden,
                ),
                child: const Text('open'),
              ),
            ),
          );
          if (!fromPushedPage) return page();
          return Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
              child: const Text('page'),
            ),
          );
        },
      ),
    ),
  ));
  if (fromPushedPage) {
    await tester.tap(find.text('page'));
    await tester.pumpAndSettle();
  }
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
  group('the dish photo', () {
    const url = 'http://fitsync.test/storage/foods/tinola.jpg';
    Finder photo() => find.descendant(of: find.byType(LogPlateSheet), matching: find.byType(DishPhoto));
    // The photo itself, without the margin drawn under it.
    Finder box() => find.descendant(of: photo(), matching: find.byType(RawImage));

    testWidgets("a full-width 16:9 photo under the sheet's title, 12 dp above the rest", (tester) async {
      final asked = fakeDishPhotos();
      // A 390 dp phone: the sheet's content is 390 - 2 x 18 = 354 wide.
      await _open(tester, plate: plateJson(tinolaJson, photoUrl: url), size: const Size(390, 1400));
      await decodeDishPhotos(tester);
      expect(asked, [url]);
      final rect = tester.getRect(box());
      expect(rect.width, closeTo(354, 0.01));
      expect(rect.height, closeTo(354 * 9 / 16, 0.01));
      final image = box();
      // Its 12 dp margin is drawn with it, under the photo.
      expect(tester.getRect(photo()).width, rect.width);
      expect(tester.getRect(photo()).bottom - rect.bottom, closeTo(12, 0.01));
      final clip = tester.widget<ClipRRect>(find.ancestor(of: image, matching: find.byType(ClipRRect)).first);
      expect(clip.borderRadius, BorderRadius.circular(FsRadius.md));
      // The handle and the header stay at the very top; the photo leads
      // the sheet's content.
      final handle = tester.getRect(find.byKey(const Key('sheet.handle')));
      final title = tester.getRect(find.text('Log to Lunch'));
      expect(handle.bottom, lessThanOrEqualTo(title.top));
      expect(rect.top, greaterThan(title.bottom));
      expect(tester.getRect(find.text('Rice')).top - rect.bottom, closeTo(12, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no taller than 200 dp on a wide screen', (tester) async {
      fakeDishPhotos();
      await _open(tester, plate: plateJson(tinolaJson, photoUrl: url), size: const Size(700, 1400));
      await decodeDishPhotos(tester);
      final rect = tester.getRect(box());
      expect(rect.height, 200);
      expect(rect.width, closeTo(tester.getSize(find.byKey(const Key('logPlate.log'))).width, 0.01),
          reason: 'as wide as the content');
    });

    testWidgets('while it loads, a box of the same size holds its place', (tester) async {
      DishPhoto.debugImage = (_, _, _) => PendingImage();
      addTearDown(() => DishPhoto.debugImage = null);
      await _open(tester, plate: plateJson(tinolaJson, photoUrl: url), size: const Size(390, 1400));
      expect(tester.getSize(find.byKey(const Key('dish.loading'))), Size(354, 354 * 9 / 16));
    });

    testWidgets('a dish without a photo: none, and the sheet starts with its header as before', (tester) async {
      final asked = fakeDishPhotos();
      await _open(tester, plate: plateJson(tinolaJson), size: const Size(390, 1400));
      expect(asked, isEmpty);
      expect(photo(), findsNothing);
      expect(find.byKey(const Key('dish.leaf')), findsNothing, reason: 'no leaf banner');
      final header = tester.getRect(find.byType(FsSheetHeader));
      expect(tester.getRect(find.text('Rice')).top - header.bottom, closeTo(8, 0.01));
    });

    testWidgets('a photo that fails: no leaf banner, no box', (tester) async {
      DishPhoto.debugImage = (_, _, _) => brokenPhoto();
      addTearDown(() => DishPhoto.debugImage = null);
      await _open(tester, plate: plateJson(tinolaJson, photoUrl: url), size: const Size(390, 1400));
      await decodeDishPhotos(tester);
      // Stretched across the column, but takes no height.
      expect(tester.getSize(photo()).height, 0);
      expect(find.byKey(const Key('dish.leaf')), findsNothing);
      expect(find.byKey(const Key('dish.loading')), findsNothing);
      // No gap left where it was: as a dish without a photo.
      final header = tester.getRect(find.byType(FsSheetHeader));
      expect(tester.getRect(find.text('Rice')).top - header.bottom, closeTo(8, 0.01));
      expect(tester.takeException(), isNull);
    });
  });

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

  group("Don't suggest this", () {
    final hideButton = find.byKey(const Key('logPlate.hide'));

    testWidgets('not offered when the caller passes no onHidden', (tester) async {
      await _open(tester, plate: plateJson(tinolaJson));
      expect(hideButton, findsNothing);
      expect(find.text("Don't suggest this"), findsNothing);
    });

    testWidgets('offered under Log plate: said with the dish, at least 48 dp tall', (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, plate: plateJson(tinolaJson), onHidden: (_) {});
      expect(find.descendant(of: hideButton, matching: find.text("Don't suggest this")), findsOneWidget);
      expect(
        tester.getSemantics(hideButton),
        isSemantics(label: "Don't suggest Tinolang manok", isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(tester.getSize(hideButton).height, greaterThanOrEqualTo(48));
      expect(
        tester.getRect(hideButton).top,
        greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('logPlate.log'))).bottom),
        reason: 'under Log plate',
      );
      semantics.dispose();
    });

    testWidgets('a tap hides the dish, tells the caller and closes the sheet', (tester) async {
      final hidden = <SuggestedFood>[];
      final (repo, _, logged) = await _open(tester, plate: plateJson(tinolaJson), onHidden: hidden.add);
      await tester.tap(hideButton);
      await tester.pumpAndSettle();
      expect(repo.hideCalls, [10]);
      expect(hidden.map((d) => (d.foodId, d.name)), [(10, 'Tinolang manok')]);
      expect(find.byType(LogPlateSheet), findsNothing, reason: 'the sheet closed');
      expect(logged.calls, isEmpty, reason: 'nothing logged');
      expect(repo.calls.where((c) => c.startsWith('log ')), isEmpty);
    });

    testWidgets('while hiding, Log plate is disabled and the button shows busy', (tester) async {
      final semantics = tester.ensureSemantics();
      final hidden = <SuggestedFood>[];
      final (repo, _, _) = await _open(tester, plate: plateJson(tinolaJson), onHidden: hidden.add);
      final hold = repo.hiddenHold = Completer<void>();
      await tester.tap(hideButton);
      await tester.pump();
      expect(tester.widget<FsButton>(find.byKey(const Key('logPlate.log'))).onPressed, isNull);
      expect(tester.widget<TextButton>(hideButton).onPressed, isNull);
      expect(find.descendant(of: hideButton, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.descendant(of: hideButton, matching: find.text("Don't suggest this")), findsNothing);
      expect(tester.getSemantics(hideButton), isSemantics(label: "Don't suggest Tinolang manok", isButton: true, isEnabled: false));
      expect(hidden, isEmpty);
      // The barrier does nothing meanwhile, as while saving.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(find.byType(LogPlateSheet), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(hidden, hasLength(1));
      expect(find.byType(LogPlateSheet), findsNothing);
      semantics.dispose();
    });

    // The sheet stays mounted for its exit animation after a drag, while its
    // route is already popping: a hide landing then must not pop the page
    // under it.
    testWidgets('dragged away mid-hide, a hide that goes through still tells the caller and keeps the page', (tester) async {
      final hidden = <SuggestedFood>[];
      final (repo, _, _) = await _open(tester, plate: plateJson(tinolaJson), onHidden: hidden.add, fromPushedPage: true);
      final hold = repo.hiddenHold = Completer<void>();
      await tester.tap(hideButton);
      await tester.pump();
      final height = tester.getSize(find.byType(LogPlateSheet)).height;
      await tester.drag(find.byKey(const Key('sheet.handle')), Offset(0, height * 0.55));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byType(LogPlateSheet), findsOneWidget, reason: 'still sliding away');

      hold.complete();
      await tester.pumpAndSettle();
      expect(repo.hideCalls, [10]);
      expect(hidden.map((d) => d.foodId), [10]);
      expect(find.byType(LogPlateSheet), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: 'the page under the sheet stays');
      expect(find.text('page'), findsNothing);
    });

    testWidgets('a failure stays in the sheet, says why and lets the user try again', (tester) async {
      final hidden = <SuggestedFood>[];
      final (repo, _, _) = await _open(tester, plate: plateJson(tinolaJson), onHidden: hidden.add);
      repo.failHidden = true;
      await tester.tap(hideButton);
      await tester.pumpAndSettle();
      expect(find.byType(LogPlateSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('logPlate.hideError')),
          matching: find.text("Couldn't hide it. Something went wrong on our side. Please try again."),
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(hideButton).onPressed, isNotNull, reason: 'enabled again');
      expect(find.descendant(of: hideButton, matching: find.text("Don't suggest this")), findsOneWidget);
      expect(tester.widget<FsButton>(find.byKey(const Key('logPlate.log'))).onPressed, isNotNull);
      expect(hidden, isEmpty);

      // A second try clears the message and goes through.
      repo.failHidden = false;
      await tester.tap(hideButton);
      await tester.pumpAndSettle();
      expect(repo.hideCalls, [10, 10]);
      expect(hidden, hasLength(1));
      expect(find.byType(LogPlateSheet), findsNothing);
    });

    testWidgets('gone once Log plate is tapped, so the two never race', (tester) async {
      final (repo, _, _) = await _open(tester, plate: plateJson(tinolaJson), onHidden: (_) {});
      expect(hideButton, findsOneWidget);
      final hold = repo.hold = Completer<void>();
      repo.failNext = true;
      await tester.tap(find.byKey(const Key('logPlate.log')));
      await tester.pump();
      expect(hideButton, findsNothing, reason: 'saving');
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LogPlateSheet), findsOneWidget, reason: 'a failed save keeps the sheet open');
      expect(hideButton, findsNothing, reason: 'after a failed save, Retry only');
    });
  });
}
