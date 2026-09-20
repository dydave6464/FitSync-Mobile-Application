import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_charts.dart';

void main() {
  testWidgets('every bar keeps its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FsBars(
            color: Colors.amber,
            bars: [
              FsBar(label: 'M', value: 3),
              FsBar(label: 'T', value: 5),
              FsBar(label: 'W', value: 0),
            ],
          ),
        ),
      ),
    );

    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-zero bars draw without dividing by zero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FsBars(
            color: Colors.amber,
            bars: [
              FsBar(label: 'M', value: 0),
              FsBar(label: 'T', value: 0),
            ],
          ),
        ),
      ),
    );

    // A rest week is genuinely all zeroes, and scaling against the largest
    // value means the largest is zero too.
    expect(tester.takeException(), isNull);
  });
}
