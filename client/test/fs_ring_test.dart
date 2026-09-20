import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_charts.dart';

/// The exact double `_RingPainter.paint()` multiplies its value by. Kept as
/// the same literal (rather than recomputed from `2 * math.pi`) so the
/// expected sweep angle is bit-identical to what the widget draws --
/// `PaintPattern.arc`'s sweepAngle check is an exact `==`, not a tolerance.
const double _twoPi = 6.283185307179586;

/// From twelve o'clock -- the start angle the value arc is drawn from.
const double _twelveOClock = -1.5707963267948966;

/// The CustomPaint FsRing wraps around its child. Reading real canvas calls
/// off this (via the `paints` matcher below) is what proves `paint()` drew
/// the right arc -- reading the painter's `value` field only proves the
/// number was threaded into the constructor, which a hardcoded sweep angle
/// in `paint()` itself would leave untouched.
Finder get _ringCanvas => find.descendant(
  of: find.byType(FsRing),
  matching: find.byType(CustomPaint),
);

void main() {
  testWidgets('the ring draws its child in the middle and sweeps by value', (
    tester,
  ) async {
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

    // Exactly one full-circle track arc, then one value arc swept to
    // 2*pi*0.32 in the widget's own colour -- a hardcoded sweep (e.g. always
    // half a circle) would still pass a `value` field read but fails this.
    expect(_ringCanvas, paintsExactlyCountTimes(#drawArc, 2));
    expect(
      _ringCanvas,
      paints
        ..arc(startAngle: 0, sweepAngle: _twoPi)
        ..arc(
          startAngle: _twelveOClock,
          sweepAngle: _twoPi * 0.32,
          color: Colors.amber,
        ),
    );
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

      if (value.isNaN || value <= 0) {
        // Both degrade to a non-positive fraction, and `paint()` returns
        // right after the track for those -- no value arc is drawn at all,
        // rather than one with a nonsensical (negative or NaN) sweep.
        expect(
          _ringCanvas,
          paintsExactlyCountTimes(#drawArc, 1),
          reason: 'value $value should draw only the track, no value arc',
        );
      } else {
        // 2.0 clamps to 1.0: a full circle, not a sweep of 2*pi*2.0.
        expect(_ringCanvas, paintsExactlyCountTimes(#drawArc, 2));
        expect(
          _ringCanvas,
          paints
            ..arc(startAngle: 0, sweepAngle: _twoPi)
            ..arc(
              startAngle: _twelveOClock,
              sweepAngle: _twoPi,
              color: Colors.amber,
            ),
          reason: 'value $value should clamp to exactly one full sweep',
        );
      }
    }
  });
}
