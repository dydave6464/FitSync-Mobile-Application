import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../exercises/presentation/providers.dart' show apiClientProvider;
import '../../data/meal_photo_picker.dart';
import '../../data/meal_photo_repository.dart';

final mealPhotoRepositoryProvider = Provider<MealPhotoRepository>(
  (ref) => MealPhotoRepository(ref.watch(apiClientProvider)),
);

/// Injectable for tests, which have no camera.
final mealPhotoPickerProvider = Provider<MealPhotoPicker>(
  (ref) => const ImagePickerMealPhotoPicker(),
);

/// Opens FitSync's page in the phone's Settings (to turn the camera on).
final appSettingsOpenerProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ph.openAppSettings();
  },
);
