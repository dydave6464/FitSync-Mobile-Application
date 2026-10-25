import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/data/meal_photo_picker.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/capture_choice_sheet.dart';

Future<void> _host(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onTap,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onTap(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the capture sheet offers the camera and the library', (
    tester,
  ) async {
    PhotoSource? picked;
    var closed = false;
    await _host(tester, (context) async {
      picked = await showCaptureChoiceSheet(context);
      closed = true;
    });
    expect(find.text('Snap a meal'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from library'), findsOneWidget);
    await tester.tap(find.byKey(const Key('snap.library')));
    await tester.pumpAndSettle();
    expect([picked, closed], [PhotoSource.library, true]);
  });

  testWidgets('each capture choice is a 48 dp target', (tester) async {
    await _host(tester, (context) => showCaptureChoiceSheet(context));
    for (final key in ['snap.camera', 'snap.library']) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('camera refused: says why, and offers Settings or the library', (
    tester,
  ) async {
    var settingsOpened = 0;
    bool? useLibrary;
    await _host(tester, (context) async {
      useLibrary = await showCameraDeniedDialog(
        context,
        openSettings: () async => settingsOpened++,
      );
    });
    expect(find.text('Camera is off for FitSync'), findsOneWidget);
    expect(
      find.text(
        'FitSync needs the camera to see your meal. Turn it on in Settings, or choose a photo from your library.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('snap.denied.settings')));
    await tester.pumpAndSettle();
    expect([settingsOpened, useLibrary], [1, false]);

    await _host(tester, (context) async {
      useLibrary = await showCameraDeniedDialog(
        context,
        openSettings: () async => settingsOpened++,
      );
    });
    await tester.tap(find.byKey(const Key('snap.denied.library')));
    await tester.pumpAndSettle();
    expect([settingsOpened, useLibrary], [1, true]);
  });
}
