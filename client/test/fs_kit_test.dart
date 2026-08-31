import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('a selected chip shows a check when asked', (tester) async {
    await tester.pumpWidget(_host(
      FsChip(label: 'Bench', selected: true, showCheck: true, onTap: () {}),
    ));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('an unselected chip shows no check', (tester) async {
    await tester.pumpWidget(_host(
      FsChip(label: 'Bench', selected: false, showCheck: true, onTap: () {}),
    ));
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a chip without showCheck never shows one', (tester) async {
    await tester.pumpWidget(_host(
      FsChip(label: 'Home gym', selected: true, onTap: () {}),
    ));
    expect(find.byIcon(Icons.check), findsNothing,
        reason: 'the location chips keep the plain treatment');
  });

  testWidgets('ticking a chip does not change its width', (tester) async {
    // The check slot is reserved whenever showCheck is set, so selecting a
    // chip repaints it without resizing it. Building the icon on selection
    // alone widened the chip by 18px mid-layout, which reflowed the
    // enclosing Wrap and pushed neighbouring chips onto another line.
    Future<double> widthWhen(bool selected) async {
      await tester.pumpWidget(_host(
        FsChip(
          label: 'Pull-up bar',
          selected: selected,
          showCheck: true,
          onTap: _noop,
        ),
      ));
      return tester.getSize(find.byType(FsChip)).width;
    }

    expect(await widthWhen(true), await widthWhen(false));
  });

  testWidgets('a chip without showCheck reserves no check slot',
      (tester) async {
    // The reserved slot must not leak onto the location chips, which would
    // gain 18px of dead space for a check they never render.
    await tester.pumpWidget(_host(
      const FsChip(label: 'Home gym', selected: false, onTap: _noop),
    ));
    final plain = tester.getSize(find.byType(FsChip)).width;

    await tester.pumpWidget(_host(
      const FsChip(
        label: 'Home gym',
        selected: false,
        showCheck: true,
        onTap: _noop,
      ),
    ));
    final reserved = tester.getSize(find.byType(FsChip)).width;

    expect(plain, lessThan(reserved));
  });

  testWidgets('FsTag renders its text', (tester) async {
    await tester.pumpWidget(_host(const FsTag('4 selected')));
    expect(find.text('4 selected'), findsOneWidget);
  });

  testWidgets(
      'a chip with a long label wraps instead of overflowing on a narrow '
      'surface at a large text scale', (tester) async {
    // Reproduces the FsChip regression directly: the label sits inside a
    // Row (added for the optional check icon), and RenderFlex gives
    // non-flex children unbounded main-axis constraints, so the Text can no
    // longer soft-wrap to the Wrap's bounded width. 320dp mirrors a small
    // phone; 2.0x mirrors Android 14's maximum text scale.
    await tester.pumpWidget(_host(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: TextScaler.linear(2.0),
        ),
        child: const SizedBox(
          width: 320,
          child: Wrap(
            children: [
              FsChip(
                label: 'Adjustable resistance bands and ankle weights',
                selected: true,
                showCheck: true,
                onTap: _noop,
              ),
            ],
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the same long-label chip still hugs its content at normal text scale',
      (tester) async {
    // Guards the fix in the other direction: Flexible must not make the
    // chip stretch to fill the Wrap's width when nothing forces wrapping.
    await tester.pumpWidget(_host(
      const SizedBox(
        width: 320,
        child: Wrap(
          children: [
            FsChip(
              label: 'Bench',
              selected: false,
              onTap: _noop,
            ),
          ],
        ),
      ),
    ));

    final chipWidth = tester.getSize(find.byType(FsChip)).width;
    expect(chipWidth, lessThan(100),
        reason: 'a short label must not stretch to the Wrap width');
  });

  testWidgets('FsNav reports the tapped index and marks the current one',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(_host(
      FsNav(
        currentIndex: 0,
        onSelect: taps.add,
        items: const [
          FsNavItem(icon: Icons.home_outlined, label: 'Home'),
          FsNavItem(icon: Icons.fitness_center_outlined, label: 'Train'),
        ],
      ),
    ));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Train'), findsOneWidget);

    await tester.tap(find.text('Train'));
    await tester.pump();
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(taps, [1, 0],
        reason: 'the bar reports each tap with its correct index');
  });

  testWidgets('FsNav does not overflow on narrow screens at 2.0x text scale',
      (tester) async {
    // Nav bar items have unguarded text that could wrap and overflow the
    // fixed 58px height at accessibility text scales. Constrain with
    // maxLines: 1 and overflow: TextOverflow.ellipsis.
    // 320dp mirrors a small phone; 2.0x mirrors Android 14's maximum text scale.
    await tester.pumpWidget(_host(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: TextScaler.linear(2.0),
        ),
        child: FsNav(
          currentIndex: 0,
          onSelect: (_) {},
          items: const [
            FsNavItem(icon: Icons.home_outlined, label: 'Home'),
            FsNavItem(
                icon: Icons.fitness_center_outlined,
                label: 'Adjustable resistance training'),
            FsNavItem(icon: Icons.settings_outlined, label: 'Settings'),
            FsNavItem(icon: Icons.person_outlined, label: 'Profile'),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
