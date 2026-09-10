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

void main() {
  testWidgets('without onFabTap the bar is unchanged', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('nav.fab')), findsNothing);
    for (var i = 0; i < 4; i += 1) {
      expect(find.byKey(Key('nav.$i')), findsOneWidget);
    }
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
}
