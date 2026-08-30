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
  test('defaults to dark, because the design is dark-first', () async {
    final container =
        _containerWith(ThemeStore(backing: InMemorySecureStore()));

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('restores a saved light preference', () async {
    final backing = InMemorySecureStore();
    final store = ThemeStore(backing: backing);
    await store.write(ThemeMode.light);

    final container = _containerWith(store);
    // build() returns the default synchronously and loads the stored value
    // right after, so the restored mode lands on the next microtask.
    expect(container.read(themeModeProvider), ThemeMode.dark);
    await container.read(themeModeProvider.notifier).ready;

    expect(container.read(themeModeProvider), ThemeMode.light);
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

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
