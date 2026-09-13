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

  testWidgets('the raised top of the fab is tappable', (tester) async {
    var taps = 0;
    await _pump(tester, onFabTap: () => taps += 1);

    final rect = tester.getRect(find.byKey(const Key('nav.fab')));
    // Near the top edge of the circle -- the part that rises above the bar.
    // A Transform.translate moves paint but not the ancestors' hit-test box,
    // so this is precisely where a naive raise stops registering.
    await tester.tapAt(Offset(rect.center.dx, rect.top + 6));
    expect(taps, 1);
  });

  testWidgets('the fab bar grows with the bottom inset', (tester) async {
    // The bar is Container(1px top border) + SafeArea(inset) + 58, and the
    // fab needs its RISE above that -- 4, which is all it takes to put the
    // circle's centre on the tab icons' line. Pinning the total to a constant
    // instead makes the bar taller than the box that holds it at every real
    // inset -- iPhone home indicator 34, Android 3-button 48 -- and Stack's
    // default Clip.hardEdge eats the difference silently.
    for (final inset in [0.0, 24.0, 34.0, 48.0]) {
      await _pumpInset(tester, inset);
      expect(
        tester.getSize(find.byType(FsNav)).height,
        59 + 4 + inset,
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

  testWidgets('the fab centres on the tab icons rather than riding above them',
      (tester) async {
    // The design's `margin-top: -14px` is measured from CENTRED, not from the
    // bar's top edge: `.botnav` centres the circle like every other item and
    // the negative margin lifts it from there. Reading it as "14 above the
    // edge" double-counts the half-difference between the bar and the circle
    // and leaves the "+" floating over the tabs instead of breaking their
    // line -- which is what a device showed.
    //
    // Asserted against the tab icons rather than a constant, because "aligned
    // with the other items" is the thing that was wrong; the bar's own height
    // is free to change without making this a lie.
    for (final inset in [0.0, 34.0, 48.0]) {
      await _pumpInset(tester, inset);
      final fab = tester.getRect(find.byKey(const Key('nav.fab')));
      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('nav.0')),
          matching: find.byType(Icon),
        ),
      );
      expect(
        icon.center.dy - fab.center.dy,
        closeTo(0, 1.5),
        reason: 'the circle must sit on the icons\' line, not above it '
            '(inset $inset)',
      );
    }
  });

  testWidgets('the raised cap of the fab stays inside the bar\'s own box',
      (tester) async {
    // The circle has to break the bar's edge to be the design's fab, but
    // every pixel of it must still sit inside FsNav's reported box: a raised
    // top that spills outside is painted, not hit-tested, and the tap dies
    // before it reaches the InkWell.
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
          reason: 'the raised cap is outside the hit-test box (inset $inset)');
      expect(
        tester.getRect(decorated).top,
        greaterThan(fab.top),
        reason: 'the circle must break the bar edge, not sit under it '
            '(inset $inset)',
      );
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
