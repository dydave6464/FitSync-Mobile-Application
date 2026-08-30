import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_store.dart';

/// Remembers whether the user chose dark or light.
///
/// Rides on the same [SecureStore] the JWT uses rather than adding
/// `shared_preferences` for one string. That costs a little — encrypted
/// storage is heavier than it needs to be for a display preference — and buys
/// two things: no new dependency, and the existing [InMemorySecureStore]
/// double keeps every widget test off the platform channel with no new
/// plumbing.
class ThemeStore {
  ThemeStore({this._backing = const PluginSecureStore()});

  static const _key = 'fitsync.themeMode';
  final SecureStore _backing;

  Future<ThemeMode?> read() async => switch (await _backing.read(_key)) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        // Anything else — absent, or written by a future version that knew
        // about more modes — means "no usable preference", so the caller
        // keeps its default rather than guessing.
        _ => null,
      };

  Future<void> write(ThemeMode mode) =>
      _backing.write(_key, mode == ThemeMode.light ? 'light' : 'dark');
}

final themeStoreProvider = Provider<ThemeStore>((ref) => ThemeStore());

/// The design is dark-first, so that is what an unconfigured install gets.
const _defaultMode = ThemeMode.dark;

class ThemeController extends Notifier<ThemeMode> {
  /// Completes once the stored preference has been applied.
  ///
  /// `build()` has to return synchronously — `MaterialApp.themeMode` cannot
  /// await — so the stored value is read immediately afterwards. Tests await
  /// this instead of relying on pump timing.
  late Future<void> ready;

  /// Set once the user picks a mode, so a slow restore cannot overwrite it.
  bool _chosen = false;

  @override
  ThemeMode build() {
    _chosen = false;
    ready = _restore();
    return _defaultMode;
  }

  Future<void> _restore() async {
    final saved = await ref.read(themeStoreProvider).read();
    // If the user toggled while this read was in flight, their choice wins —
    // otherwise the stored value would land afterwards and silently undo it.
    if (saved != null && !_chosen) state = saved;
  }

  Future<void> setDark(bool dark) async {
    _chosen = true;
    state = dark ? ThemeMode.dark : ThemeMode.light;
    await ref.read(themeStoreProvider).write(state);
  }
}

final themeModeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);
