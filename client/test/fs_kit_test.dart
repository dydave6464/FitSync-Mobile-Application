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
}

void _noop() {}
