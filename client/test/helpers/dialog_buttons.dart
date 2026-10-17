import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';

/// The text button labelled [label] inside the dialog that is showing, so a
/// button of the same name on the screen behind it is never the one found.
Finder dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(TextButton, label),
);

/// The colour [button]'s label is actually painted in, theme included.
Color? labelColor(WidgetTester tester, Finder button) => tester
    .renderObject<RenderParagraph>(
      find.descendant(of: button, matching: find.byType(RichText)).first,
    )
    .text
    .style
    ?.color;

/// The red the showing dialog's theme gives destructive choices.
Color dialogRed(WidgetTester tester) =>
    tester.element(find.byType(AlertDialog)).fs.red;
