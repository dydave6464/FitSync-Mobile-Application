import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/sessions/data/rest_alerts.dart';

/// A keystore that will not answer, as one can on a phone with a locked or
/// corrupted keychain.
class _BrokenStore implements SecureStore {
  @override
  Future<String?> read(String key) async => throw Exception('keystore');
  @override
  Future<void> write(String key, String value) async =>
      throw Exception('keystore');
  @override
  Future<void> delete(String key) async => throw Exception('keystore');
}

void main() {
  group('RestAlertStore', () {
    test('alerts are on until switched off', () async {
      final store = RestAlertStore(backing: InMemorySecureStore());

      expect(await store.enabled(), isTrue);
      await store.setEnabled(false);
      expect(await store.enabled(), isFalse);
      await store.setEnabled(true);
      expect(await store.enabled(), isTrue);
    });

    test('remembers that this phone was asked', () async {
      final store = RestAlertStore(backing: InMemorySecureStore());

      expect(await store.asked(), isFalse);
      await store.markAsked();
      expect(await store.asked(), isTrue);
    });

    // An unreadable keystore must cost the alert's settings, never the
    // workout -- and must not turn into a permission prompt on every rest.
    test('a keystore that fails reads as on, already asked', () async {
      final store = RestAlertStore(backing: _BrokenStore());

      expect(await store.enabled(), isTrue);
      expect(await store.asked(), isTrue);
      await store.setEnabled(false);
      await store.markAsked();
    });
  });

  test('restAlertEnabledProvider reads and writes the store', () async {
    final store = RestAlertStore(backing: InMemorySecureStore());
    final container = ProviderContainer(
      overrides: [restAlertStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(await container.read(restAlertEnabledProvider.future), isTrue);
    await container.read(restAlertEnabledProvider.notifier).set(false);

    expect(container.read(restAlertEnabledProvider).value, isFalse);
    expect(await store.enabled(), isFalse);
  });
}
