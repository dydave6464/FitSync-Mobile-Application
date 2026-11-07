import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// FitSync's mark as the app icon draws it (logo concept 12, "Motion
/// blades"): green blades on the dark tile, with the hairline edge that keeps
/// the tile visible on a dark background.
///
/// The colours come from the dark palette in both themes on purpose: the mark
/// is the brand, and it must look the same on the sign-in screen as on the
/// phone's home screen. The launcher icon sources in assets/icon/ were
/// rendered once from [FitBladesPainter] (the blades at 22/34 of a 1024
/// square, on [FsTokens.dark]'s surface2 for the full icon and on transparent
/// for Android's adaptive foreground). Nothing re-renders them: if the blades
/// change, render both again the same way and run
/// `dart run flutter_launcher_icons`.
class FsBrandMark extends StatelessWidget {
  const FsBrandMark({super.key, this.size = 34});

  /// The tile's side. The blades take two thirds of it and the corners are
  /// rounded by a third, as the prototype's 34 dp tile with 22 dp blades and
  /// 11 dp corners.
  final double size;

  @override
  Widget build(BuildContext context) {
    const brand = FsTokens.dark;

    return Container(
      key: const Key('brand.tile'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brand.surface2,
        borderRadius: BorderRadius.circular(size * 11 / 34),
        border: Border.all(color: brand.line2),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        key: const Key('logo.blades'),
        size: Size.square(size * 22 / 34),
        painter: FitBladesPainter(brand.accent),
      ),
    );
  }
}

/// FitSync's mark, the prototype's `FitBlades` (kit.jsx): one blade drawn
/// three times, turned 0, 120 and 240 degrees about the centre, each fainter
/// than the last.
class FitBladesPainter extends CustomPainter {
  const FitBladesPainter(this.color);

  final Color color;

  static const _opacities = [1.0, 0.6, 0.32];

  @override
  void paint(Canvas canvas, Size size) {
    // The SVG's 100-unit box, scaled to [size].
    final scale = size.shortestSide / 100;
    final blade = Path()
      ..moveTo(50, 50)
      ..cubicTo(52, 30, 62, 18, 80, 22)
      ..cubicTo(70, 38, 66, 46, 50, 50)
      ..close();

    canvas
      ..save()
      ..scale(scale);
    for (var i = 0; i < _opacities.length; i++) {
      canvas.drawPath(
        blade,
        Paint()..color = color.withValues(alpha: _opacities[i]),
      );
      canvas
        ..translate(50, 50)
        ..rotate(2 * math.pi / 3)
        ..translate(-50, -50);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FitBladesPainter old) => old.color != color;
}
