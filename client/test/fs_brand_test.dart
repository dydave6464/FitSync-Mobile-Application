import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {bool dark = false}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: dark ? fsDarkTheme() : fsLightTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

BoxDecoration _tile(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(FsBrandMark),
      matching: find.byKey(const Key('brand.tile')),
    ),
  );
  return box.decoration! as BoxDecoration;
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('the mark is the app icon: green blades on the dark tile '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await _pump(tester, const FsBrandMark(), dark: dark);

      final tile = _tile(tester);
      expect(tile.color, FsTokens.dark.surface2);
      expect(tile.border, Border.all(color: FsTokens.dark.line2));

      final paint = tester.widget<CustomPaint>(
        find.byKey(const Key('logo.blades')),
      );
      expect((paint.painter! as FitBladesPainter).color, FsTokens.dark.accent);
    });
  }

  testWidgets('the tile is 34 and the blades two thirds of it by default', (
    tester,
  ) async {
    await _pump(tester, const FsBrandMark());

    expect(tester.getSize(find.byKey(const Key('brand.tile'))).width, 34);
    expect(tester.getSize(find.byKey(const Key('logo.blades'))).width, 22);
  });

  testWidgets('the mark scales as one piece', (tester) async {
    await _pump(tester, const FsBrandMark(size: 68));

    expect(tester.getSize(find.byKey(const Key('brand.tile'))).width, 68);
    expect(tester.getSize(find.byKey(const Key('logo.blades'))).width, 44);
    expect(_tile(tester).borderRadius, BorderRadius.circular(22));
  });

  testWidgets('three blades fade from full to 60 % to 32 %', (tester) async {
    await _pump(tester, const FsBrandMark());

    final alphas = <double>[];
    expect(
      find.byKey(const Key('logo.blades')),
      paints..everything((method, args) {
        for (final arg in args) {
          if (arg is Paint) alphas.add(arg.color.a);
        }
        return true;
      }),
    );
    expect(alphas.length, 3);
    expect(alphas[0], closeTo(1.0, 0.01));
    expect(alphas[1], closeTo(0.6, 0.01));
    expect(alphas[2], closeTo(0.32, 0.01));
  });
}
