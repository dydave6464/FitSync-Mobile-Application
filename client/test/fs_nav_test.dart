import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

const _items = [
  FsNavItem(icon: Icons.home_outlined, label: 'Home'),
  FsNavItem(icon: Icons.fitness_center_outlined, label: 'Train'),
  FsNavItem(icon: Icons.menu_book_outlined, label: 'Browse'),
  FsNavItem(icon: Icons.person_outline, label: 'Profile'),
];

Future<void> _pump(WidgetTester tester, {VoidCallback? onFabTap}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        bottomNavigationBar: FsNav(
          currentIndex: 0,
          onSelect: (_) {},
          items: _items,
          onFabTap: onFabTap,
        ),
      ),
    ),
  );
}


/// The same bar, pumped at a real phone's viewport and bottom inset rather
/// than the harness default of 800x600 with a zero inset. The inset is the
/// one axis nothing in this repo varies, and it is the axis the bar's own
/// SafeArea grows on.
Future<void> _pumpInset(WidgetTester tester, double inset) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          padding: EdgeInsets.only(bottom: inset),
        ),
        child: Scaffold(
          bottomNavigationBar: FsNav(
            currentIndex: 0,
            onSelect: (_) {},
            items: _items,
            onFabTap: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('without onFabTap the bar is unchanged', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('nav.fab')), findsNothing);
    for (var i = 0; i < 4; i += 1) {
      expect(find.byKey(Key('nav.$i')), findsOneWidget);
    }
    // Pins the bar's height so a fab-present layout change (the extra space
    // above the bar for the raised circle) can't silently leak into the
    // no-fab path, which every screen's body height still depends on. 59,
    // not 58: Container already pads its child by the top BorderSide's own
    // width, pre-existing and unrelated to the fab.
    expect(tester.getSize(find.byType(FsNav)).height, 59);
  });

  testWidgets('the fab renders and reports taps', (tester) async {
    var taps = 0;
    await _pump(tester, onFabTap: () => taps += 1);

    expect(find.byKey(const Key('nav.fab')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav.fab')));
    expect(taps, 1);
  });

  testWidgets('the fab does not renumber the tabs', (tester) async {
    // The whole reason the fab is not an item: nav_shell_test taps nav.0
    // through nav.3 in ten places, and Browse must stay 2, not become 3.
    await _pump(tester, onFabTap: () {});
    for (var i = 0; i < 4; i += 1) {
      expect(find.byKey(Key('nav.$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('nav.4')), findsNothing);
  });

  testWidgets('the fab sits between Train and Browse', (tester) async {
    await _pump(tester, onFabTap: () {});
    final train = tester.getCenter(find.byKey(const Key('nav.1'))).dx;
    final fab = tester.getCenter(find.byKey(const Key('nav.fab'))).dx;
    final browse = tester.getCenter(find.byKey(const Key('nav.2'))).dx;
    expect(fab, greaterThan(train));
    expect(fab, lessThan(browse));
  });

  testWidgets('the top of the fab is tappable', (tester) async {
    var taps = 0;
    await _pump(tester, onFabTap: () => taps += 1);

    final rect = tester.getRect(find.byKey(const Key('nav.fab')));
    // Near the top edge of the circle. Kept from when the circle rose above
    // the bar and this was the exact spot a naive raise stopped registering:
    // it is still the first place a layout change would break the tap.
    await tester.tapAt(Offset(rect.center.dx, rect.top + 6));
    expect(taps, 1);
  });

  testWidgets('the fab bar grows with the bottom inset', (tester) async {
    // The bar is Container(1px top border) + SafeArea(inset) + 58, and the
    // fab now sits INSIDE that row rather than above it, so a fab bar and a
    // fab-less bar are the same height. Pinning the total to a constant
    // instead makes the bar taller than the box that holds it at every real
    // inset -- iPhone home indicator 34, Android 3-button 48 -- and the
    // difference is eaten silently.
    for (final inset in [0.0, 24.0, 34.0, 48.0]) {
      await _pumpInset(tester, inset);
      expect(
        tester.getSize(find.byType(FsNav)).height,
        59 + inset,
        reason: 'the fab bar must reserve the inset, not swallow it (inset $inset)',
      );
    }
  });

  testWidgets('a bottom inset does not clip the tab icons', (tester) async {
    // What the height above actually costs when it is wrong: the bar
    // bottom-anchors inside a box too short for it, so its top -- the tab
    // icons -- is pushed above the box and clipped away. No RenderFlex
    // assertion fires, so takeException() stays null and the suite stays
    // green while a phone shows half an icon.
    for (final inset in [34.0, 48.0]) {
      await _pumpInset(tester, inset);
      final bar = tester.getRect(find.byType(FsNav));
      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('nav.0')),
          matching: find.byType(Icon),
        ),
      );
      expect(
        icon.top,
        greaterThanOrEqualTo(bar.top),
        reason: 'the tab icon is cut off at the top of the bar (inset $inset)',
      );
      expect(icon.bottom, lessThanOrEqualTo(bar.bottom));
    }
  });

  testWidgets('the fab centres on the tab cell, level with the row',
      (tester) async {
    // Centred on the whole tab CELL -- icon over label -- not on the icon
    // alone. Centring on the icon line is what two rounds of device feedback
    // called out: it puts the circle's centre 8px above the block the tabs
    // actually occupy, so the one item that is not a tab is the one item out
    // of line.
    //
    // Asserted against the tab cell rather than a constant, because "level
    // with the other items" is the property; the bar's own height is free to
    // change without making this a lie.
    for (final inset in [0.0, 34.0, 48.0]) {
      await _pumpInset(tester, inset);
      final fab = tester.getRect(find.byKey(const Key('nav.fab')));
      final cell = tester.getRect(find.byKey(const Key('nav.0')));
      expect(
        cell.center.dy - fab.center.dy,
        closeTo(0, 0.5),
        reason: 'the circle must sit level with the tab cells (inset $inset)',
      );
    }
  });

  testWidgets('the fab sits wholly inside the bar', (tester) async {
    // The circle no longer breaks the bar's top edge: it is a child of the
    // same row as the tabs, so every pixel of it is inside both FsNav's
    // reported box and the decorated bar itself. Anything outside that box is
    // painted but not hit-tested, and the tap dies before the InkWell.
    for (final inset in [0.0, 34.0, 48.0]) {
      await _pumpInset(tester, inset);
      final fab = tester.getRect(find.byKey(const Key('nav.fab')));
      final bar = tester.getRect(find.byType(FsNav));
      final decorated = find.descendant(
        of: find.byType(FsNav),
        matching: find.byType(Container),
      );
      expect(decorated, findsOneWidget, reason: 'the bar is one decorated box');

      expect(fab.top, greaterThanOrEqualTo(bar.top),
          reason: 'the fab is outside the hit-test box (inset $inset)');
      expect(
        fab.top,
        greaterThanOrEqualTo(tester.getRect(decorated).top),
        reason: 'the circle must sit inside the bar, not over its edge '
            '(inset $inset)',
      );
      expect(fab.bottom, lessThanOrEqualTo(bar.bottom));
    }
  });

  testWidgets('the fab casts the accent drop shadow the design gives it',
      (tester) async {
    // styles.css puts a glow under the raised circle, the same one it puts
    // under .btn.primary. A bare Material has none: the circle reads as
    // painted onto the bar rather than lifted off it, which is the whole
    // point of the shape.
    await _pump(tester, onFabTap: () {});

    final shadowed = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: find.byType(FsNav), matching: find.byType(DecoratedBox)),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.boxShadow?.isNotEmpty ?? false)
        .toList();

    expect(shadowed, hasLength(1),
        reason: 'the raised fab is the one thing in this bar that lifts off it');
    // Round, not square: a rectangular glow under a circle is worse than none.
    expect(shadowed.single.shape, BoxShape.circle);

    final accent = fsLightTheme().extension<FsTokens>()!.accent;
    final shadow = shadowed.single.boxShadow!.single;
    expect(shadow.color, accent.withValues(alpha: 0.45));
    expect(shadow.offset, const Offset(0, 10));
    expect(shadow.blurRadius, 24);
    expect(shadow.spreadRadius, -10);
  });
}
