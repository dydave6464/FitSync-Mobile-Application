import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';

import 'helpers/a11y.dart';

void main() {
  testWidgets('draws the handle, the title and a labelled Close', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const FsSheetHeader(title: 'Jump to an exercise')),
    );

    expect(find.text('Jump to an exercise'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('sheet.handle'))),
      const Size(38, 4),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(
      tester.getSize(find.byType(IconButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  // P-21: closeKey was never passed, so it keyed nothing. Every sheet's ×
  // now carries one key, which a caller may still replace.
  testWidgets('the close button has a key by default, or the one given', (
    tester,
  ) async {
    await tester.pumpWidget(host(const FsSheetHeader(title: 'Rest')));
    expect(
      find.descendant(
        of: find.byKey(FsSheetHeader.defaultCloseKey),
        matching: find.byTooltip('Close'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      host(const FsSheetHeader(title: 'Rest', closeKey: Key('rest.close'))),
    );
    expect(find.byKey(const Key('rest.close')), findsOneWidget);
    expect(find.byKey(FsSheetHeader.defaultCloseKey), findsNothing);
  });

  testWidgets('Close calls onClose when given one', (tester) async {
    var closes = 0;
    await tester.pumpWidget(
      host(FsSheetHeader(title: 'Rest', onClose: () => closes++)),
    );

    await tester.tap(find.byTooltip('Close'));
    expect(closes, 1);
  });

  testWidgets('a long title wraps at 2x text on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        const FsSheetHeader(title: 'How did your last workout leave you?'),
        textScale: 2.0,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('meets the tap-target and contrast guidelines in both themes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        host(const FsSheetHeader(title: 'Share with coach'), dark: dark),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
    handle.dispose();
  });
}
