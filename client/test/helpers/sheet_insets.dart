import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';

/// P-21: the open sheet's title starts, and its ×'s 48 dp button ends,
/// [FsSheetHeader.sideInset] from the sheet's edges. Every sheet's test
/// checks against the same number, so the × is in the same place on every
/// sheet, not only symmetric within one.
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
  expect(sheet.right - close.right, FsSheetHeader.sideInset, reason: 'the ×');
  expect(heading.left - sheet.left, FsSheetHeader.sideInset, reason: 'title');
}
