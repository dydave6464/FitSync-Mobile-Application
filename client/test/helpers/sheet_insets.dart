import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';

/// P-21: the open sheet's title starts, and its ×'s 48 dp button ends,
/// [FsSheetHeader.sideInset] from the sheet's edges. Every sheet's test
/// checks against the same number, so the × is in the same place on every
/// sheet, not only symmetric within one.
///
/// A header with a [FsSheetHeader.leading] icon starts with that icon
/// instead, so the icon is what sits at the inset and the title follows it.
void expectSheetHeaderAtSideInset(
  WidgetTester tester, {
  required String title,
}) {
  // The sheet's own surface: on a wide test window Material centres a
  // sheet at most 640 dp wide inside the BottomSheet's full-width box.
  final sheet = tester.getRect(
    find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        )
        .first,
  );
  final close = tester.getRect(find.widgetWithIcon(IconButton, Icons.close));
  final heading = tester.getRect(
    find.descendant(of: find.byType(BottomSheet), matching: find.text(title)),
  );
  // Not every sheet draws FsSheetHeader (the start sheet has its own), and
  // one that does not has no leading icon either.
  final headers = find
      .descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(FsSheetHeader),
      )
      .evaluate();
  final leading = headers.isEmpty
      ? null
      : (headers.single.widget as FsSheetHeader).leading;
  expect(sheet.right - close.right, FsSheetHeader.sideInset, reason: 'the ×');
  if (leading == null) {
    expect(heading.left - sheet.left, FsSheetHeader.sideInset, reason: 'title');
  } else {
    final icon = tester.getRect(find.byWidget(leading));
    expect(icon.left - sheet.left, FsSheetHeader.sideInset, reason: 'leading');
    expect(heading.left, greaterThan(icon.right), reason: 'title after icon');
  }
}
