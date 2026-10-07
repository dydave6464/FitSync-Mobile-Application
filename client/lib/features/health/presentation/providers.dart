import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart' show apiClientProvider;
import '../data/health_repository.dart';
import '../domain/health_answers.dart';

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(apiClientProvider)),
);

/// The stored health check, or null. Read only by the Settings editor, so it
/// is disposed when that closes; writers invalidate it after saving.
final healthProvider = FutureProvider.autoDispose<HealthAnswers?>(
  (ref) => ref.watch(healthRepositoryProvider).getHealth(),
);
