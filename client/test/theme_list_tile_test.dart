import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';

// X-1: listTileTheme.subtitleTextStyle named no font, and ListTile does not
// merge it with the text theme, so a subtitle (the library row's muscle and
// equipment line) drew in the platform font rather than the app's. The
// title, set from the text theme before the app font was applied, too.
void main() {
  for (final (name, theme) in [
    ('light', fsLightTheme()),
    ('dark', fsDarkTheme()),
  ]) {
    testWidgets('a ListTile subtitle draws in the app font ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: ListTile(
              title: Text('Squat'),
              subtitle: Text('Quads · Barbell'),
            ),
          ),
        ),
      );

      TextStyle drawn(String text) => tester
          .widget<RichText>(
            find.descendant(
              of: find.text(text),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!;
      // The title had the same gap: the theme set it from the text theme
      // before ThemeData applied the app font to it.
      expect(drawn('Squat').fontFamily, 'SpaceGrotesk');
      expect(drawn('Quads · Barbell').fontFamily, 'SpaceGrotesk');
    });
  }
}
