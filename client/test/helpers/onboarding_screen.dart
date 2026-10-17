import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lays [step] out on a phone [screenWidth] dp wide at [textScale], inside
/// the 20dp side gutters `OnboardingScaffold` and `EditScaffold` give a step.
///
/// The test surface itself is resized. Wrapping the step in a `MediaQuery`
/// with a narrow `size` would only change what MediaQuery reports: the
/// layout would still get the default 800dp-wide surface, and an overflow at
/// 320dp would never be laid out, let alone caught.
Future<void> pumpOnPhone(
  WidgetTester tester,
  Widget step, {
  required double screenWidth,
  double textScale = 2.0,
}) async {
  tester.view.physicalSize = Size(screenWidth, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: step,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The two phone widths every step is checked on: the narrowest Android
/// phone (a 280dp step), and the common 360dp one (a 320dp step).
const phoneWidths = [320.0, 360.0];
