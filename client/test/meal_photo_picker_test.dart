import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fitsync/features/nutrition/data/meal_photo_picker.dart';

/// Stands in for the platform plugin: records what the picker asked for and
/// hands back [file], as the plugin hands back its own resized copy.
class _FakePlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _FakePlatform(this.file);

  final XFile? file;
  ImageSource? source;
  ImagePickerOptions? options;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    this.source = source;
    this.options = options;
    return file;
  }
}

const _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2];

void main() {
  late Directory dir;
  setUp(
    () async =>
        dir = await Directory.systemTemp.createTemp('meal_photo_picker_test'),
  );
  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File copyOf(List<int> bytes) =>
      File('${dir.path}/picked.jpg')..writeAsBytesSync(bytes);

  test(
    'asks for a 768 px photo at quality 80, without full metadata',
    () async {
      final fake = _FakePlatform(XFile(copyOf(_jpeg).path));
      ImagePickerPlatform.instance = fake;
      final photo = await const ImagePickerMealPhotoPicker().pick(
        PhotoSource.camera,
      );
      expect(fake.source, ImageSource.camera);
      expect(fake.options!.maxWidth, 768);
      expect(fake.options!.imageQuality, 80);
      expect(fake.options!.requestFullMetadata, isFalse);
      expect(photo!.mimeType, 'image/jpeg');
      expect(photo.bytes, _jpeg);
    },
  );

  test('the photo library is the gallery', () async {
    final fake = _FakePlatform(XFile(copyOf(_jpeg).path));
    ImagePickerPlatform.instance = fake;
    await const ImagePickerMealPhotoPicker().pick(PhotoSource.library);
    expect(fake.source, ImageSource.gallery);
  });

  test(
    "deletes the plugin's copy once it is read: the photo is not kept",
    () async {
      final copy = copyOf(_jpeg);
      ImagePickerPlatform.instance = _FakePlatform(XFile(copy.path));
      await const ImagePickerMealPhotoPicker().pick(PhotoSource.camera);
      expect(copy.existsSync(), isFalse);
    },
  );

  test(
    "a photo that is neither JPEG nor PNG is refused, and its copy deleted too",
    () async {
      final copy = copyOf([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]); // HEIC
      ImagePickerPlatform.instance = _FakePlatform(XFile(copy.path));
      await expectLater(
        const ImagePickerMealPhotoPicker().pick(PhotoSource.library),
        throwsA(isA<UnsupportedPhoto>()),
      );
      expect(copy.existsSync(), isFalse);
    },
  );

  test('backing out of the camera returns null', () async {
    ImagePickerPlatform.instance = _FakePlatform(null);
    expect(
      await const ImagePickerMealPhotoPicker().pick(PhotoSource.camera),
      isNull,
    );
  });
}
