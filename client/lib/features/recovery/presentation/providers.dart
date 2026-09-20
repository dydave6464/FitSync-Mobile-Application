import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/recovery_repository.dart';
import '../domain/recovery.dart';

final recoveryRepositoryProvider = Provider<RecoveryRepository>(
  (ref) => RecoveryRepository(ref.watch(apiClientProvider)),
);

final recoveryOverviewProvider = FutureProvider<RecoveryOverview>(
  (ref) => ref.watch(recoveryRepositoryProvider).overview(),
  retry: apiRetryPolicy,
);
