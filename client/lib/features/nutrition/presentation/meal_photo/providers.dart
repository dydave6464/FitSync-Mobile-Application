import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../exercises/presentation/providers.dart' show apiClientProvider;
import '../../data/meal_photo_picker.dart';
import '../../data/meal_photo_repository.dart';

// The Settings opener lives in core now (Home and Reminders use it too);
// still offered from here, where Snap a meal and its tests find it.
export '../../../../core/app_settings.dart' show appSettingsOpenerProvider;

final mealPhotoRepositoryProvider = Provider<MealPhotoRepository>(
  (ref) => MealPhotoRepository(ref.watch(apiClientProvider)),
);

/// Injectable for tests, which have no camera.
final mealPhotoPickerProvider = Provider<MealPhotoPicker>(
  (ref) => const ImagePickerMealPhotoPicker(),
);
