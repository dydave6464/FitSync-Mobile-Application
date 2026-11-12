import 'package:flutter_riverpod/flutter_riverpod.dart';

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
