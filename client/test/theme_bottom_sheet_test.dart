import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

// PT-22: every sheet draws one chrome -- the surface, the card's 22 dp top
// corners and the prototype's 38 x 4 line2 handle -- from the theme, rather
// than each call choosing its own or getting Material's 28 dp defaults.
void main() {
  for (final (name, theme, tokens) in [
    ('light', fsLightTheme(), FsTokens.light),
    ('dark', fsDarkTheme(), FsTokens.dark),
  ]) {
    test('the $name theme gives every sheet the kit chrome', () {
      final sheet = theme.bottomSheetTheme;
      expect(sheet.backgroundColor, tokens.surface);
      expect(sheet.showDragHandle, isTrue);
      expect(sheet.dragHandleColor, tokens.line2);
      expect(sheet.dragHandleSize, const Size(38, 4));
      expect(
        sheet.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(FsRadius.card),
          ),
        ),
      );
    });
  }

  testWidgets('FsSheetHandle is the same 38 x 4 line2 pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: const Scaffold(body: Center(child: FsSheetHandle())),
      ),
    );

    expect(tester.getSize(find.byType(FsSheetHandle)), const Size(38, 4));
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(FsSheetHandle),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, FsTokens.light.line2);
  });
}
