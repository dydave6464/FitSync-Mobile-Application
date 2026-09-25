import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/token_store.dart' show PluginSecureStore, SecureStore;

/// Whether Home's one-time reminder prompt has already been answered --
/// Turn on or Not now, either counts -- so it is shown at most once.
///
/// Beside [TokenStore] for the same reason: behind an interface so tests
/// never touch the platform channel, which needs a running Android or iOS
/// host and would make every widget test that renders the card require a
/// device.
class ReminderPromptStore {
  ReminderPromptStore({this._backing = const PluginSecureStore()});

  static const _key = 'reminder_prompt_answered';
  final SecureStore _backing;

  Future<bool> answered() async => await _backing.read(_key) == 'true';
  Future<void> markAnswered() => _backing.write(_key, 'true');
}

final reminderPromptStoreProvider = Provider<ReminderPromptStore>(
  (ref) => ReminderPromptStore(),
);
