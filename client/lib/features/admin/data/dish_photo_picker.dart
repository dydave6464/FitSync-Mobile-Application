import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../nutrition/data/meal_photo_picker.dart'
    show PickedPhoto, UnsupportedPhoto, pickedPhotoFrom;

/// Where the food form gets a dish's photo: the phone's gallery. An
/// interface so tests never reach the platform plugin.
abstract interface class DishPhotoPicker {
  /// The photo and the type its bytes really are, or null when the admin
  /// backed out. Throws [UnsupportedPhoto] for anything but a JPEG or PNG,
  /// the two the server takes.
  Future<PickedPhoto?> pick();
}

class GalleryDishPhotoPicker implements DishPhotoPicker {
  const GalleryDishPhotoPicker();

  @override
  Future<PickedPhoto?> pick() async {
    // At most 800 px on the longest side and quality 80: sharp on the Log
    // sheet's full-width banner, and well under the server's 1.5 MB.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    return pickedPhotoFrom(file);
  }
}

/// Injectable for tests, which have no gallery.
final dishPhotoPickerProvider = Provider<DishPhotoPicker>(
  (ref) => const GalleryDishPhotoPicker(),
);
