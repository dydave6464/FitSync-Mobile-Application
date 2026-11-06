import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../data/meal_photo_picker.dart';
import '../../domain/meal_photo.dart';
import 'meal_photo_screen.dart' show photosLeftText;

/// What the capture sheet chose: a new photo, or today's unlogged one.
sealed class CaptureChoice {
  const CaptureChoice();
}

/// A new photo from the camera or the library.
final class CapturePhoto extends CaptureChoice {
  const CapturePhoto(this.source);

  final PhotoSource source;
}

/// Today's recognised photo that was not logged, opened again. Costs no
/// photo: the server already has its answer.
final class CaptureResume extends CaptureChoice {
  const CaptureResume(this.recognition);

  final PhotoRecognition recognition;
}

/// '2 foods · not logged yet': what the Finish tile says about [r].
String unloggedText(PhotoRecognition r) {
  final n = r.foodCount;
  return '$n ${n == 1 ? 'food' : 'foods'} · not logged yet';
}

/// Camera or photo library, as a bottom sheet. Null when dismissed.
///
/// [today] is asked as the sheet opens; the sheet does not wait for it.
/// Its answer only adds below the two choices -- how many photos are left
/// once few are, and today's unlogged photo -- so nothing moves under a
/// finger; with none left the two choices are off. A failed or slow answer
/// adds nothing: the photo call still enforces the limit.
Future<CaptureChoice?> showCaptureChoiceSheet(
  BuildContext context, {
  Future<PhotoToday>? today,
}) {
  // A failure is never reported, even one that comes before the sheet
  // listens.
  today?.ignore();
  return _sheet(context, today);
}

Future<CaptureChoice?> _sheet(
  BuildContext context,
  Future<PhotoToday>? today,
) => showModalBottomSheet<CaptureChoice>(
  context: context,
  showDragHandle: true,
  builder: (sheet) => FutureBuilder<PhotoToday>(
    future: today,
    builder: (sheet, snapshot) {
      final t = sheet.fs;
      final known = snapshot.hasData ? snapshot.data : null;
      final noneLeft = known != null && known.remainingToday <= 0;
      final left = known == null ? null : photosLeftText(known.remainingToday);
      final unlogged = known?.unlogged;
      // Scrolls rather than overflows when large text makes it taller
      // than the sheet may be.
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Snap a meal',
                    style: Theme.of(sheet).textTheme.titleMedium,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Text(
                  'AI suggests the food — you confirm & log.',
                  style: TextStyle(color: t.text2, fontSize: 13),
                ),
              ),
              ListTile(
                key: const Key('snap.camera'),
                minTileHeight: 48,
                enabled: !noneLeft,
                leading: Icon(Icons.photo_camera_outlined, color: t.text2),
                title: const Text('Take a photo'),
                onTap: () =>
                    Navigator.of(sheet)
                        .pop(const CapturePhoto(PhotoSource.camera)),
              ),
              ListTile(
                key: const Key('snap.library'),
                minTileHeight: 48,
                enabled: !noneLeft,
                leading: Icon(Icons.photo_library_outlined, color: t.text2),
                title: const Text('Choose from library'),
                onTap: () =>
                    Navigator.of(sheet)
                        .pop(const CapturePhoto(PhotoSource.library)),
              ),
              if (left != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    left,
                    key: const Key('snap.sheetLeft'),
                    style: TextStyle(color: t.text2, fontSize: 13),
                  ),
                ),
              // Stays on with no photos left: reopening costs none.
              if (unlogged != null)
                ListTile(
                  key: const Key('snap.resume'),
                  minTileHeight: 48,
                  leading: Icon(Icons.restore, color: t.text2),
                  title: const Text('Finish your last photo'),
                  subtitle: Text(unloggedText(unlogged)),
                  onTap: () => Navigator.of(sheet).pop(CaptureResume(unlogged)),
                ),
            ],
          ),
        ),
      );
    },
  ),
);

/// Why the camera is needed, with both ways forward. True when the user
/// chose the photo library instead; false after Open Settings or dismissal.
Future<bool> showCameraDeniedDialog(
  BuildContext context, {
  required Future<void> Function() openSettings,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Camera is off for FitSync'),
      content: const Text(
        'FitSync needs the camera to see your meal. Turn it on in Settings, or choose a photo from your library.',
      ),
      actions: [
        TextButton(
          key: const Key('snap.denied.settings'),
          onPressed: () => Navigator.of(dialog).pop('settings'),
          child: const Text('Open Settings'),
        ),
        TextButton(
          key: const Key('snap.denied.library'),
          onPressed: () => Navigator.of(dialog).pop('library'),
          child: const Text('Choose from library'),
        ),
      ],
    ),
  );
  if (choice == 'settings') await openSettings();
  return choice == 'library';
}
