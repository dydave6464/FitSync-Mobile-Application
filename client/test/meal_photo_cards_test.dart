import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/domain/meal_photo.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/photo_cards.dart';

const _rice = Food(source: 'local', id: 1, name: 'White rice', servingDesc: '1 cup (160 g)', kcal: 206, proteinG: 3.4, carbsG: 47.5, fatG: 0.3);
const _garlic = Food(source: 'local', id: 2, name: 'Garlic fried rice (sinangag)', servingDesc: '1 cup (160 g)', kcal: 299, proteinG: 4.2, carbsG: 56.3, fatG: 6.4);

DraftCard _card({double servings = 1.5, List<Food> alts = const [_garlic]}) => DraftCard.suggested(
  PhotoSuggestion(itemId: 40, confidence: 0.9, servings: servings, food: _rice, alternatives: alts),
);

Future<void> _pump(WidgetTester tester, Widget child, {double width = 400, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: fsLightTheme(),
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: child)),
  ));
}

void main() {
  testWidgets('an item card shows the food, its other guesses, Search and the portion', (tester) async {
    Food? swapped;
    double? servings;
    var searched = 0, removed = 0;
    await _pump(tester, PhotoItemCard(
      index: 0, card: _card(),
      onSwap: (f) => swapped = f, onSearch: () => searched++, onServings: (s) => servings = s, onRemove: () => removed++,
    ));
    expect(find.text('White rice'), findsOneWidget);
    expect(find.text('Not right? Pick another:'), findsOneWidget);
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('1.5 × 1 cup (160 g) · 309 kcal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('snap.alt.0.0')));
    expect(swapped, _garlic);
    await tester.tap(find.byKey(const Key('snap.search.0')));
    await tester.tap(find.byKey(const Key('snap.plus.0')));
    expect(servings, 2.0);
    await tester.tap(find.byKey(const Key('snap.minus.0')));
    expect(servings, 1.0);
    await tester.tap(find.byKey(const Key('snap.remove.0')));
    expect([searched, removed], [1, 1]);
  });

  testWidgets('with no other guesses it still offers Search', (tester) async {
    await _pump(tester, PhotoItemCard(index: 0, card: _card(alts: const []), onSwap: (_) {}, onSearch: () {}, onServings: (_) {}, onRemove: () {}));
    expect(find.text('Not right?'), findsOneWidget);
    expect(find.byKey(const Key('snap.search.0')), findsOneWidget);
  });

  testWidgets('the stepper stops at half a serving', (tester) async {
    await _pump(tester, PhotoItemCard(index: 0, card: _card(servings: 0.5), onSwap: (_) {}, onSearch: () {}, onServings: (_) {}, onRemove: () {}));
    final minus = tester.widget<IconButton>(find.byKey(const Key('snap.minus.0')));
    expect(minus.onPressed, isNull);
  });

  testWidgets('screen readers hear what each control does', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, PhotoItemCard(index: 0, card: _card(), onSwap: (_) {}, onSearch: () {}, onServings: (_) {}, onRemove: () {}));
    expect(find.bySemanticsLabel('Swap to Garlic fried rice (sinangag)'), findsOneWidget);
    expect(find.bySemanticsLabel('Search for another food'), findsOneWidget);
    expect(find.byTooltip('Remove White rice'), findsOneWidget);
    expect(find.byTooltip('Less White rice'), findsOneWidget);
    expect(find.byTooltip('More White rice'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('snap.portion.0'))),
      isSemantics(isLiveRegion: true, label: 'White rice: 1.5 × 1 cup (160 g) · 309 kcal'),
    );
    handle.dispose();
  });

  testWidgets('every control is a 48 dp target', (tester) async {
    await _pump(tester, PhotoItemCard(index: 0, card: _card(), onSwap: (_) {}, onSearch: () {}, onServings: (_) {}, onRemove: () {}));
    for (final key in ['snap.remove.0', 'snap.minus.0', 'snap.plus.0']) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width >= 48 && size.height >= 48, isTrue, reason: key);
    }
  });

  testWidgets('a chip on the second row still answers a tap 7 dp past its edge', (tester) async {
    const brown = Food(source: 'local', id: 3, name: 'Brown rice', servingDesc: '1 cup (160 g)', kcal: 216, proteinG: 5, carbsG: 45, fatG: 1.8);
    var searched = 0;
    await _pump(tester, PhotoItemCard(
      index: 0, card: _card(alts: const [_garlic, brown]),
      onSwap: (_) {}, onSearch: () => searched++, onServings: (_) {}, onRemove: () {},
    ), width: 320);
    final first = tester.getRect(find.descendant(of: find.byKey(const Key('snap.alt.0.0')), matching: find.byType(FsChip)));
    final search = tester.getRect(find.descendant(of: find.byKey(const Key('snap.search.0')), matching: find.byType(FsChip)));
    expect(search.top, greaterThan(first.bottom), reason: 'Search should wrap to a second row');
    await tester.tapAt(Offset(search.center.dx, search.top - 7));
    await tester.tapAt(Offset(search.center.dx, search.bottom + 7));
    expect(searched, 2);
  });

  testWidgets('a not-in-the-list card names the item and offers a search', (tester) async {
    var searched = 0, removed = 0;
    await _pump(tester, PhotoUnlistedCard(
      index: 1, card: DraftCard.unlisted(const PhotoUnlisted(itemId: 42, name: 'Atchara (pickled papaya)')),
      onSearch: () => searched++, onRemove: () => removed++,
    ));
    expect(find.text('"Atchara (pickled papaya)" isn\'t in FitSync\'s list'), findsOneWidget);
    await tester.tap(find.byKey(const Key('snap.unlisted.search.1')));
    await tester.tap(find.byKey(const Key('snap.remove.1')));
    expect([searched, removed], [1, 1]);
    expect(find.byTooltip('Remove Atchara (pickled papaya)'), findsOneWidget);
  });

  testWidgets('the total card shows kcal and the three macros', (tester) async {
    await _pump(tester, const PhotoTotalCard(totals: MacroTotals(kcal: 608, proteinG: 9.3, carbsG: 127.55, fatG: 6.85, fiberG: 0, sugarG: 0, sodiumMg: 0)));
    expect(find.text('Estimated total'), findsOneWidget);
    expect(find.text('608 kcal'), findsOneWidget);
    expect(find.text('9 g'), findsOneWidget);
    expect(find.text('128 g'), findsOneWidget);
    expect(find.text('7 g'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the cards fit a 320 dp phone at ${scale}x text', (tester) async {
      await _pump(tester, Column(children: [
        PhotoItemCard(index: 0, card: _card(), onSwap: (_) {}, onSearch: () {}, onServings: (_) {}, onRemove: () {}),
        PhotoUnlistedCard(index: 1, card: DraftCard.unlisted(const PhotoUnlisted(itemId: 42, name: 'Atchara (pickled papaya)')), onSearch: () {}, onRemove: () {}),
        const PhotoTotalCard(totals: MacroTotals(kcal: 608, proteinG: 9.3, carbsG: 127.55, fatG: 6.85, fiberG: 0, sugarG: 0, sodiumMg: 0)),
      ]), width: 320, scale: scale);
      expect(tester.takeException(), isNull);
    });
  }
}
