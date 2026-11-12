import 'package:flutter/material.dart';

import 'package:fitsync/core/theme.dart';

/// Hosts [child] centred in a Scaffold, in either theme, at a given text
/// scale. For a small screen, set `tester.view.physicalSize` and
/// `devicePixelRatio` instead.
Widget host(Widget child, {bool dark = false, double textScale = 1.0}) {
  Widget app = MaterialApp(
    theme: dark ? fsDarkTheme() : fsLightTheme(),
    home: Scaffold(body: Center(child: child)),
  );
  if (textScale != 1.0) {
    app = MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: app,
    );
  }
  return app;
}

/// WCAG contrast, compositing translucent colours onto [background] first.
double contrast(Color fg, Color background) {
  final a = Color.alphaBlend(fg, background).computeLuminance();
  final b = background.computeLuminance();
  final hi = a > b ? a : b, lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}
