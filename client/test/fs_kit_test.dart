import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('a selected chip shows a check when asked', (tester) async {
    await tester.pumpWidget(_host(
      FsChip(label: 'Bench', selected: true, showCheck: true, onTap: () {}),
    ));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('an unselected chip shows no check', (tester) async {
    await tester.pumpWidget(_host(
      FsChip(label: 'Bench', selected: false, showCheck: true, onTap: () {}),
    ));
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a chip without showCheck never shows one', (tester) async {
    await tester.pumpWidget(_host(
      FsChip(label: 'Home gym', selected: true, onTap: () {}),
    ));
    expect(find.byIcon(Icons.check), findsNothing,
        reason: 'the location chips keep the plain treatment');
  });

  testWidgets('FsTag renders its text', (tester) async {
    await tester.pumpWidget(_host(const FsTag('4 selected')));
    expect(find.text('4 selected'), findsOneWidget);
  });
}
