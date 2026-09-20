import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_charts.dart';

/// Reaches past FsRing's SizedBox to the CustomPaint it wraps and reads the
/// value its (private) painter was built with. This is what makes the tests
/// below fail if the ring stops actually drawing its input -- a hardcoded
/// sweep angle would leave `find.text` and `takeException` satisfied while
/// this catches it.
double _ringValue(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(
    find
        .descendant(of: find.byType(FsRing), matching: find.byType(CustomPaint))
        .first,
  );
  return (customPaint.painter as dynamic).value as double;
}

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
    expect(_ringValue(tester), closeTo(0.32, 1e-9));
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

      final painted = _ringValue(tester);
      expect(painted.isFinite, isTrue, reason: 'value $value painted $painted');
      expect(
        painted,
        inInclusiveRange(0.0, 1.0),
        reason: 'value $value painted $painted',
      );
      if (value.isNaN) {
        // Not finite input has no sane fraction, so it degrades to an empty
        // ring rather than carrying the NaN through to the canvas.
        expect(painted, 0.0, reason: 'NaN should degrade to an empty ring');
      } else if (value < 0) {
        expect(
          painted,
          0.0,
          reason: 'value $value should clamp to the low end',
        );
      } else {
        expect(
          painted,
          1.0,
          reason: 'value $value should clamp to the high end',
        );
      }
    }
  });
}
