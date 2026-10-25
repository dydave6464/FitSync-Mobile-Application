import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/meal_photo.dart';

enum PhotoSource { camera, library }

/// A meal photo ready to send: its bytes and the type they really are.
class PickedPhoto {
  const PickedPhoto(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;
}

/// The camera is off for FitSync (refused now or before).
class CameraAccessDenied implements Exception {
  const CameraAccessDenied();
}

/// The photo is neither a JPEG nor a PNG, the two the server takes.
class UnsupportedPhoto implements Exception {
  const UnsupportedPhoto();
}

/// Where Snap a meal gets its photo. An interface so tests never reach the
/// platform plugin.
abstract interface class MealPhotoPicker {
  /// The photo, or null when the user backed out. Throws [CameraAccessDenied]
  /// or [UnsupportedPhoto].
  Future<PickedPhoto?> pick(PhotoSource source);
}

class ImagePickerMealPhotoPicker implements MealPhotoPicker {
  const ImagePickerMealPhotoPicker();

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    final XFile? file;
    try {
      // 1024 px and quality 80 keep a photo around 150-300 KB -- plenty for
      // naming food, quick to send, well under the server's 1.5 MB.
      file = await ImagePicker().pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 80,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied') throw const CameraAccessDenied();
      rethrow;
    }
    if (file == null) return null;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } finally {
      // The photo is not kept: the bytes are all the app needs.
      _deleteCopy(file);
    }
    final type = sniffImageType(bytes);
    if (type == null) throw const UnsupportedPhoto();
    return PickedPhoto(bytes, type);
  }

  /// Deletes the file image_picker returned. It is always the plugin's own
  /// copy in the app's tmp or cache folder (resized, or copied out of the
  /// gallery), never the original in the user's photos. Best effort: a copy
  /// left behind is cleared by the OS in time.
  static void _deleteCopy(XFile file) {
    if (kIsWeb) return; // a blob URL on the web, not a file
    try {
      File(file.path).deleteSync();
    } catch (_) {}
  }
}
