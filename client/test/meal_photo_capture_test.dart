import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_picker.dart';
import 'package:fitsync/features/nutrition/domain/meal_photo.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/capture_choice_sheet.dart';

Map<String, dynamic> _food(int id) => {
  'id': id,
  'name': 'Food $id',
  'servingDesc': '1 cup',
  'fromFatsecret': false,
  'perServing': {'kcal': 100, 'proteinG': 1, 'carbsG': 20, 'fatG': 1, 'fiberG': null, 'sugarG': null, 'sodiumMg': null},
};

PhotoRecognition _recognition({required int items, required int unlisted}) => PhotoRecognition.fromJson({
  'recognitionId': 41,
  'remainingToday': 12,
  'items': [
    for (var i = 0; i < items; i++) {'itemId': 80 + i, 'confidence': 0.9, 'servings': 1, 'food': _food(i + 1), 'alternatives': []},
  ],
  'unlisted': [
    for (var i = 0; i < unlisted; i++) {'itemId': 90 + i, 'name': 'Atchara'},
  ],
});

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
    CaptureChoice? picked;
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
    expect([(picked as CapturePhoto).source, closed], [PhotoSource.library, true]);
  });

  // NU-15: the allowance shows before a photo is taken, once few are left.
  group("today's allowance", () {
    Future<List<CaptureChoice?>> openWith(WidgetTester tester, Future<PhotoToday> Function() today) async {
      final picked = <CaptureChoice?>[];
      await _host(tester, (context) async => picked.add(await showCaptureChoiceSheet(context, today: today())));
      return picked;
    }

    bool enabled(WidgetTester tester, String key) => tester.widget<ListTile>(find.byKey(Key(key))).enabled;

    testWidgets('3 left: says so under the choices', (tester) async {
      await openWith(tester, () => Future.value(const PhotoToday(limit: 15, remainingToday: 3)));
      expect(find.text('3 photos left today'), findsOneWidget);
      final caption = tester.widget<Text>(find.byKey(const Key('snap.sheetLeft')));
      expect(caption.style?.fontSize, 13);
      expect(
        tester.getTopLeft(find.byKey(const Key('snap.sheetLeft'))).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('snap.library'))).dy - 1),
        reason: 'added below the tiles, so nothing moves under a finger',
      );
      expect([enabled(tester, 'snap.camera'), enabled(tester, 'snap.library')], [true, true]);
    });

    testWidgets('1 left says it in the singular', (tester) async {
      await openWith(tester, () => Future.value(const PhotoToday(limit: 15, remainingToday: 1)));
      expect(find.text('1 photo left today'), findsOneWidget);
    });

    testWidgets('6 left: nothing added', (tester) async {
      await openWith(tester, () => Future.value(const PhotoToday(limit: 15, remainingToday: 6)));
      expect(find.byKey(const Key('snap.sheetLeft')), findsNothing);
      expect(find.byKey(const Key('snap.resume')), findsNothing);
    });

    testWidgets('none left: both choices are off', (tester) async {
      final picked = await openWith(tester, () => Future.value(const PhotoToday(limit: 15, remainingToday: 0)));
      expect(find.text('No meal photos left today'), findsOneWidget);
      expect([enabled(tester, 'snap.camera'), enabled(tester, 'snap.library')], [false, false]);
      await tester.tap(find.byKey(const Key('snap.camera')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(picked, isEmpty, reason: 'the sheet stays open');
    });

    testWidgets('the sheet opens at once, before the answer', (tester) async {
      final gate = Completer<PhotoToday>();
      await openWith(tester, () => gate.future);
      expect(find.byKey(const Key('snap.camera')), findsOneWidget);
      expect(find.byKey(const Key('snap.sheetLeft')), findsNothing);
      gate.complete(const PhotoToday(limit: 15, remainingToday: 2));
      await tester.pumpAndSettle();
      expect(find.text('2 photos left today'), findsOneWidget);
    });

    testWidgets('a failed question leaves the sheet as it was', (tester) async {
      await openWith(tester, () => Future.error(const ApiException('NETWORK_ERROR', 'x')));
      expect(find.byKey(const Key('snap.sheetLeft')), findsNothing);
      expect(find.byKey(const Key('snap.resume')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect([enabled(tester, 'snap.camera'), enabled(tester, 'snap.library')], [true, true]);
    });

    // #21: today's unlogged photo can be finished.
    testWidgets('an unlogged photo is offered, and picking it returns it', (tester) async {
      final picked = await openWith(tester, () => Future.value(PhotoToday(limit: 15, remainingToday: 12, unlogged: _recognition(items: 1, unlisted: 1))));
      expect(find.text('Finish your last photo'), findsOneWidget);
      expect(find.text('2 foods · not logged yet'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('snap.resume'))).height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const Key('snap.resume')));
      await tester.pumpAndSettle();
      expect((picked.single as CaptureResume).recognition.recognitionId, 41);
    });

    testWidgets('one food says it in the singular', (tester) async {
      await openWith(tester, () => Future.value(PhotoToday(limit: 15, remainingToday: 12, unlogged: _recognition(items: 1, unlisted: 0))));
      expect(find.text('1 food · not logged yet'), findsOneWidget);
    });

    testWidgets('finishing a photo stays open with no photos left', (tester) async {
      await openWith(tester, () => Future.value(PhotoToday(limit: 15, remainingToday: 0, unlogged: _recognition(items: 2, unlisted: 0))));
      expect(enabled(tester, 'snap.resume'), isTrue);
      expect(enabled(tester, 'snap.camera'), isFalse);
    });

    testWidgets('everything it adds fits a 320 dp phone at 2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openWith(tester, () => Future.value(PhotoToday(limit: 15, remainingToday: 0, unlogged: _recognition(items: 2, unlisted: 1))));
      expect(find.text('No meal photos left today'), findsOneWidget);
      expect(find.text('3 foods · not logged yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no unlogged photo: no Finish tile', (tester) async {
      await openWith(tester, () => Future.value(const PhotoToday(limit: 15, remainingToday: 3)));
      expect(find.byKey(const Key('snap.resume')), findsNothing);
    });
  });

  // As the app's other sheets have it (NU-18).
  testWidgets('the capture sheet has a drag handle', (tester) async {
    await _host(tester, (context) => showCaptureChoiceSheet(context));
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle, isTrue);
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
