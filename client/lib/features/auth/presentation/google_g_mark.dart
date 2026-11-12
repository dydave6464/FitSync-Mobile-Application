import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Google's "G" in its own colours, for the Continue with Google button.
///
/// Google's sign-in branding requires the standard colour G (the gradient
/// "super G") on a light, dark or neutral button: never a one-colour glyph,
/// a redrawn icon or an outdated G. So this draws it from the official
/// sign-in asset bundle (developers.google.com/identity/branding-guidelines,
/// `signin-assets.zip`, "Show text=No" Android + Web SVG), at the size the
/// surrounding [IconTheme] asks for, with no network asset and no package.
///
/// Decorative: the button's own words name the action.
class GoogleGMark extends StatelessWidget {
  const GoogleGMark({super.key});

  @override
  Widget build(BuildContext context) {
    final size = IconTheme.of(context).size ?? 18;
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _GooglePainter()),
    );
  }
}

/// The bundle's SVG, which draws the G as a mask over a blurred colour sweep
/// and six blurred highlights, in a 20-unit box at (10, 10) of its 40-unit
/// canvas. Every number here is the SVG's own.
class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  /// The SVG's `stdDeviation="1"`, in its own units.
  static const _blur = 1.0;

  /// The conic gradient's stops: degrees and RGB, from the bundle's CSS.
  static const _sweep = <(double, Color)>[
    (0, Color(0xFFFF4641)),
    (4.14555, Color(0xFFFF4641)),
    (39.154, Color(0xFF3186FF)),
    (72.0044, Color(0xFF3186FF)),
    (96.7463, Color(0xFF00A5B7)),
    (120.897, Color(0xFF0EBC5F)),
    (154.722, Color(0xFF0EBC5F)),
    (179.136, Color(0xFF6CC400)),
    (203.588, Color(0xFFFFCC00)),
    (226.915, Color(0xFFFFD314)),
    (251.688, Color(0xFFFFCC00)),
    (273.129, Color(0xFFFF6A2B)),
    (289.305, Color(0xFFFD4641)),
    (359.593, Color(0xFFFF4641)),
    (360, Color(0xFFFF4641)),
  ];

  /// The highlights over the sweep: centre, radii, rotation in degrees and
  /// colour, in the SVG's order.
  static const _highlights = <(Offset, double, double, double, Color)>[
    (Offset(20.0496, 20.2413), 5.39634, 2.83537, 24.4473, Color(0xFF3186FF)),
    (Offset(33.3538, 18.2155), 7.43918, 3.09357, 0, Color(0xFF3186FF)),
    (Offset(25.2744, 16.2195), 7.40854, 2.37805, 0, Color(0xFFFF4641)),
    (Offset(29.5427, 12.9268), 7.40854, 2.37805, 0, Color(0xFFFF5B8B)),
    (Offset(24.4817, 19.878), 8.5061, 3.10976, 0, Color(0xFF3186FF)),
    (Offset(25.1842, 14.0197), 4.53882, 2.37805, -28.6599, Color(0xFFFF4641)),
  ];

  static Path _g() => Path()
    ..moveTo(29.3987, 18.1814)
    ..lineTo(19.9849, 18.1814)
    ..lineTo(19.9849, 22.0445)
    ..lineTo(25.3598, 22.0445)
    ..cubicTo(25.1286, 23.294, 24.4294, 24.3596, 23.3676, 25.0712)
    ..cubicTo(22.4746, 25.6716, 21.3266, 26.0211, 19.9849, 26.0211)
    ..cubicTo(17.3864, 26.0211, 15.1823, 24.2666, 14.3947, 21.9004)
    ..cubicTo(14.1952, 21.2989, 14.0853, 20.6599, 14.0853, 19.9983)
    ..cubicTo(14.0853, 19.3367, 14.1952, 18.6966, 14.3947, 18.0962)
    ..cubicTo(15.1823, 15.7311, 17.3864, 13.9755, 19.9849, 13.9755)
    ..cubicTo(21.4524, 13.9755, 22.767, 14.4816, 23.8039, 15.4713)
    ..lineTo(26.6653, 12.6057)
    ..cubicTo(24.936, 10.9908, 22.6786, 10, 19.9849, 10)
    ..cubicTo(16.0832, 10, 12.705, 12.2414, 11.0618, 15.5076)
    ..cubicTo(10.383, 16.8592, 10, 18.3834, 10, 19.9994)
    ..cubicTo(10, 21.6155, 10.383, 23.1396, 11.0618, 24.4913)
    ..cubicTo(12.705, 27.7597, 16.0832, 30, 19.9849, 30)
    ..cubicTo(22.6797, 30, 24.9485, 29.1137, 26.6018, 27.5861)
    ..cubicTo(28.4887, 25.8452, 29.5732, 23.2702, 29.5732, 20.2275)
    ..cubicTo(29.5732, 19.5182, 29.5131, 18.835, 29.3987, 18.1825)
    ..lineTo(29.3987, 18.1814)
    ..close();

  /// The sweep: CSS `conic-gradient(from 90deg, ...)`, which starts at three
  /// o'clock as Flutter's does, turned 45 degrees anticlockwise by the SVG's
  /// transform about its centre, (19.6819, 19.7927).
  static Shader _sweepShader() {
    const centre = Offset(19.6819, 19.7927);
    final turn = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..rotateZ(-math.pi / 4)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    return ui.Gradient.sweep(
      centre,
      [for (final (_, colour) in _sweep) colour],
      [for (final (degrees, _) in _sweep) degrees / 360],
      TileMode.clamp,
      0,
      2 * math.pi,
      turn.storage,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final blur = ui.ImageFilter.blur(
      sigmaX: _blur,
      sigmaY: _blur,
      tileMode: TileMode.decal,
    );
    canvas
      ..save()
      ..scale(size.shortestSide / 20)
      ..translate(-10, -10)
      ..clipPath(_g());

    // The SVG's circle of colour, blurred as one layer.
    canvas
      ..saveLayer(null, Paint()..imageFilter = blur)
      ..drawOval(
        const Rect.fromLTRB(7.25922, 6.90668, 32.9973, 32.6786),
        Paint()..shader = _sweepShader(),
      )
      ..restore();

    for (final (centre, rx, ry, degrees, colour) in _highlights) {
      canvas
        ..save()
        ..translate(centre.dx, centre.dy)
        ..rotate(degrees * math.pi / 180)
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
          Paint()
            ..color = colour
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _blur),
        )
        ..restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}
