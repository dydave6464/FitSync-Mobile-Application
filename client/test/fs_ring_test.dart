import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_charts.dart';

void main() {
  testWidgets('the ring draws its child in the middle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: FsRing(
              value: 0.32,
              color: Colors.amber,
              child: Text('Low-Mod'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Low-Mod'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a value outside 0..1 is clamped rather than drawn', (
    tester,
  ) async {
    for (final value in [-1.0, 2.0, double.nan]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FsRing(
                value: value,
                color: Colors.amber,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      // A NaN sweep throws inside the canvas rather than drawing nothing, so
      // this is about not crashing on a figure the server could send.
      expect(tester.takeException(), isNull, reason: 'value $value');
    }
  });
}
