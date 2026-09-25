import 'dart:async';

import 'package:fitsync/core/token_store.dart' show InMemorySecureStore;
import 'package:fitsync/features/reminders/data/reminder_prompt_store.dart';

/// A [ReminderPromptStore] backed by in-memory storage rather than the real
/// secure-storage plugin, and pre-answered so `ReminderPromptCard` renders
/// hidden.
///
/// `ReminderPromptCard` sits on Home, so any widget test that renders Home
/// (directly, or via `NavShell`/`AppShell`) mounts it too. Its provider's
/// default reaches the real platform channel, which never answers under
/// `flutter test` -- the read simply hangs forever, which is why the card
/// has always rendered nothing in these tests, incidentally. Overriding it
/// with an in-memory store that resolves quickly changes that: an
/// unanswered store would make the card start rendering ("Get reminders for
/// your habits"), shifting the very layout most of these tests are about.
/// Pre-answering it keeps the card hidden -- deterministically, rather than
/// by a hung platform channel -- so tests that are not about the prompt
/// itself do not have to account for it.
ReminderPromptStore inMemoryReminderPromptStore() {
  final store = ReminderPromptStore(backing: InMemorySecureStore());
  // InMemorySecureStore.write mutates its map synchronously (there is no
  // real await in the chain from markAnswered down to it), so the flag is
  // already set by the time anything reads it back.
  unawaited(store.markAnswered());
  return store;
}
