import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/token_store.dart' show InMemorySecureStore;
import 'package:fitsync/features/reminders/data/reminder_prompt_store.dart';

void main() {
  test('is not answered until marked', () async {
    final store = ReminderPromptStore(backing: InMemorySecureStore());

    expect(await store.answered(), isFalse);
  });

  test('markAnswered persists the flag', () async {
    final store = ReminderPromptStore(backing: InMemorySecureStore());

    await store.markAnswered();

    expect(await store.answered(), isTrue);
  });
}
