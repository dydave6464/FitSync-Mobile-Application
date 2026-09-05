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
    final container =
        _containerWith(ThemeStore(backing: InMemorySecureStore()));

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

    expect(container.read(themeModeProvider), ThemeMode.dark,
        reason: 'an existing user who chose dark keeps it across the change '
            'of default');
  });

  test('choosing light persists it', () async {
    final store = ThemeStore(backing: InMemorySecureStore());
    final container = _containerWith(store);

    await container.read(themeModeProvider.notifier).setDark(false);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(await store.read(), ThemeMode.light,
        reason: 'the choice must survive a restart, not just this session');
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
}
