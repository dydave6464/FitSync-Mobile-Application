import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/presentation/widgets/dish_photo.dart';

import 'fake_image_http.dart';

/// An image that never finishes loading: the placeholder stays up.
class PendingImage extends ImageProvider<PendingImage> {
  @override
  Future<PendingImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(PendingImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// A fresh 1x1 PNG each time: a MemoryImage is cached by its bytes, so no
/// test sees another's loaded image.
MemoryImage onePixelPhoto() => MemoryImage(Uint8List.fromList(onePixelPng));

/// Bytes no codec can read: the image fails.
MemoryImage brokenPhoto() => MemoryImage(Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]));

/// Every [DishPhoto] in this test draws a 1x1 PNG instead of fetching its
/// URL, and the URLs asked for are recorded; set back, with a clean image
/// cache, when the test ends.
List<String> fakeDishPhotos() {
  final asked = <String>[];
  final photos = <String, MemoryImage>{};
  imageCache
    ..clear()
    ..clearLiveImages();
  DishPhoto.debugImage = (url, _, _) {
    asked.add(url);
    return photos.putIfAbsent(url, onePixelPhoto);
  };
  addTearDown(() {
    DishPhoto.debugImage = null;
    imageCache
      ..clear()
      ..clearLiveImages();
  });
  return asked;
}

/// Lets the photos decode for real (they cannot in fake time), then settles.
Future<void> decodeDishPhotos(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
}
