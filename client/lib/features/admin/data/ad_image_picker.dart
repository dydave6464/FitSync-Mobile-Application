import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../nutrition/data/meal_photo_picker.dart'
    show PickedPhoto, UnsupportedPhoto, pickedPhotoFrom;

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
    return pickedPhotoFrom(file);
  }
}

/// Injectable for tests, which have no gallery.
final adImagePickerProvider = Provider<AdImagePicker>(
  (ref) => const GalleryAdImagePicker(),
);
