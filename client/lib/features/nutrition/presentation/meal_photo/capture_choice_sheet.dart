import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../data/meal_photo_picker.dart';

/// Camera or photo library, as a bottom sheet. Null when dismissed.
Future<PhotoSource?> showCaptureChoiceSheet(BuildContext context) =>
    showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (sheet) {
        final t = sheet.fs;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
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
                  leading: Icon(Icons.photo_camera_outlined, color: t.text2),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.of(sheet).pop(PhotoSource.camera),
                ),
                ListTile(
                  key: const Key('snap.library'),
                  minTileHeight: 48,
                  leading: Icon(Icons.photo_library_outlined, color: t.text2),
                  title: const Text('Choose from library'),
                  onTap: () => Navigator.of(sheet).pop(PhotoSource.library),
                ),
              ],
            ),
          ),
        );
      },
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
