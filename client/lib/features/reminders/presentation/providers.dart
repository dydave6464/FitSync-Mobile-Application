import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/reminder_repository.dart';
import '../domain/reminders.dart';

final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepository(ref.watch(apiClientProvider)),
);

/// Not autoDispose: the signed-in shell's ReminderSync listens to it for the
/// life of the session, so it is on sign-out's list of per-user caches.
final reminderSettingsProvider =
    AsyncNotifierProvider<ReminderSettingsController, ReminderSettings>(
      ReminderSettingsController.new,
      retry: apiRetryPolicy,
    );

class ReminderSettingsController extends AsyncNotifier<ReminderSettings> {
  @override
  Future<ReminderSettings> build() =>
      ref.watch(reminderRepositoryProvider).read();

  Future<void> patch(Map<String, dynamic> fields) async {
    state = AsyncData(await ref.read(reminderRepositoryProvider).patch(fields));
  }
}
