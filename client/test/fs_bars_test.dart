import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_charts.dart';

/// The height factors of every bar's FractionallySizedBox, in the same order
/// as the FsBar list that produced them. Reading these is what makes the
/// tests below fail if FsBars stops scaling against the largest bar -- a
/// constant heightFactor would still keep every label on screen and throw
/// nothing, which is exactly what the widget tests alone used to miss.
List<double> _heightFactors(WidgetTester tester) {
  return tester
      .widgetList<FractionallySizedBox>(
        find.descendant(
          of: find.byType(FsBars),
          matching: find.byType(FractionallySizedBox),
        ),
      )
      .map((box) => box.heightFactor!)
      .toList();
}

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

    final factors = _heightFactors(tester);
    expect(factors, hasLength(3));
    expect(factors[0], closeTo(0.6, 1e-9), reason: 'M=3 against peak 5');
    expect(factors[1], closeTo(1.0, 1e-9), reason: 'T=5 is the peak itself');
    expect(factors[2], closeTo(0.02, 1e-9), reason: 'W=0 sits at the floor');
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

    final factors = _heightFactors(tester);
    expect(factors, hasLength(2));
    expect(
      factors,
      everyElement(closeTo(0.02, 1e-9)),
      reason: 'an all-zero week should sit at the floor, not fill the column',
    );
  });

  testWidgets(
    'a negative, a NaN and an infinite bar still render finite heights',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FsBars(
              color: Colors.amber,
              bars: [
                FsBar(label: 'A', value: -5),
                FsBar(label: 'B', value: double.nan),
                FsBar(label: 'C', value: double.infinity),
                FsBar(label: 'D', value: 4),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final factors = _heightFactors(tester);
      expect(factors, hasLength(4));
      for (final factor in factors) {
        expect(
          factor.isFinite,
          isTrue,
          reason: 'heightFactor $factor must be finite',
        );
        expect(
          factor,
          greaterThanOrEqualTo(0.0),
          reason: 'heightFactor $factor must not be negative',
        );
      }
    },
  );
}
