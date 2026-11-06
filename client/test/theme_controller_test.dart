import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme_controller.dart';
import 'package:fitsync/core/token_store.dart';

ProviderContainer _containerWith(ThemeStore store) {
  final container = ProviderContainer(
    overrides: [themeStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('defaults to light, and dark is a choice the user makes', () async {
    final container = _containerWith(
      ThemeStore(backing: InMemorySecureStore()),
    );

    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('restores a saved dark preference', () async {
    final backing = InMemorySecureStore();
    final store = ThemeStore(backing: backing);
    // Saved value deliberately opposite the default: if they matched, the
    // final assertion would pass whether or not anything was restored.
    await store.write(ThemeMode.dark);

    final container = _containerWith(store);
    // build() returns the default synchronously and loads the stored value
    // right after, so the restored mode lands on the next microtask.
    expect(container.read(themeModeProvider), ThemeMode.light);
    await container.read(themeModeProvider.notifier).ready;

    expect(
      container.read(themeModeProvider),
      ThemeMode.dark,
      reason:
          'an existing user who chose dark keeps it across the change '
          'of default',
    );
  });

  test('choosing light persists it', () async {
    final store = ThemeStore(backing: InMemorySecureStore());
    final container = _containerWith(store);

    await container.read(themeModeProvider.notifier).setDark(false);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(
      await store.read(),
      ThemeMode.light,
      reason: 'the choice must survive a restart, not just this session',
    );
  });

  test('choosing dark again persists it', () async {
    final store = ThemeStore(backing: InMemorySecureStore());
    await store.write(ThemeMode.light);
    final container = _containerWith(store);

    await container.read(themeModeProvider.notifier).setDark(true);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(await store.read(), ThemeMode.dark);
  });

  test('an unrecognised stored value falls back to the default', () async {
    final backing = InMemorySecureStore();
    await backing.write('fitsync.themeMode', 'chartreuse');
    final container = _containerWith(ThemeStore(backing: backing));

    await container.read(themeModeProvider.notifier).ready;

    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  group('System, the third choice (D-1)', () {
    test('a stored System round-trips through the store', () async {
      final store = ThemeStore(backing: InMemorySecureStore());

      await store.write(ThemeMode.system);

      expect(await store.read(), ThemeMode.system);
    });

    test('each mode is stored under its own word', () async {
      final backing = InMemorySecureStore();
      final store = ThemeStore(backing: backing);

      for (final (mode, word) in [
        (ThemeMode.system, 'system'),
        (ThemeMode.light, 'light'),
        (ThemeMode.dark, 'dark'),
      ]) {
        await store.write(mode);
        expect(await backing.read('fitsync.themeMode'), word);
      }
    });

    test('a saved System is restored as ThemeMode.system', () async {
      final store = ThemeStore(backing: InMemorySecureStore());
      await store.write(ThemeMode.system);
      final container = _containerWith(store);

      await container.read(themeModeProvider.notifier).ready;

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('setMode sets and persists any of the three', () async {
      final store = ThemeStore(backing: InMemorySecureStore());
      final container = _containerWith(store);
      final controller = container.read(themeModeProvider.notifier);

      for (final mode in [ThemeMode.system, ThemeMode.dark, ThemeMode.light]) {
        await controller.setMode(mode);
        expect(container.read(themeModeProvider), mode);
        expect(await store.read(), mode);
      }
    });

    test('a fresh install still starts in light, not System', () async {
      final container = _containerWith(
        ThemeStore(backing: InMemorySecureStore()),
      );

      await container.read(themeModeProvider.notifier).ready;

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test('a choice made while the restore is in flight still wins', () async {
      final store = ThemeStore(backing: InMemorySecureStore());
      await store.write(ThemeMode.dark);
      final container = _containerWith(store);
      final controller = container.read(themeModeProvider.notifier);

      await controller.setMode(ThemeMode.system);
      await controller.ready;

      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}
