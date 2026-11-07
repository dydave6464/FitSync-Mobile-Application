import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../nutrition/data/meal_photo_picker.dart'
    show PickedPhoto, UnsupportedPhoto;
import '../../nutrition/domain/meal_photo.dart' show sniffImageType;

/// Where the ad form gets its image: the phone's gallery. An interface so
/// tests never reach the platform plugin.
abstract interface class AdImagePicker {
  /// The image and the type its bytes really are, or null when the admin
  /// backed out. Throws [UnsupportedPhoto] for anything but a JPEG or PNG,
  /// the two the server takes.
  Future<PickedPhoto?> pick();
}

class GalleryAdImagePicker implements AdImagePicker {
  const GalleryAdImagePicker();

  @override
  Future<PickedPhoto?> pick() async {
    // At most 1280 px on the longest side and quality 85: sharp on a phone's
    // card, and well under the server's 1.5 MB.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } finally {
      _deleteCopy(file);
    }
    final type = sniffImageType(bytes);
    if (type == null) throw const UnsupportedPhoto();
    return PickedPhoto(bytes, type);
  }

  /// Deletes image_picker's own copy (resized, or copied out of the
  /// gallery), never the original. Best effort, as Snap a meal's.
  static void _deleteCopy(XFile file) {
    if (kIsWeb) return;
    try {
      File(file.path).deleteSync();
    } catch (_) {}
  }
}

/// Injectable for tests, which have no gallery.
final adImagePickerProvider = Provider<AdImagePicker>(
  (ref) => const GalleryAdImagePicker(),
);
