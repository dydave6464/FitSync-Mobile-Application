import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/token_store.dart' show PluginSecureStore, SecureStore;

/// The seam between the logger's rest and the phone's notifications: the
/// one alert that says a rest is over while the phone is locked or the app is
/// in the background.
abstract interface class RestAlertScheduler {
  /// Whether this phone currently lets the app show notifications.
  Future<bool> permissionGranted();

  /// Shows the system prompt where the OS allows one; answers the result.
  Future<bool> requestPermission();

  /// The app's page in the phone's settings, where a refused permission can
  /// still be granted.
  Future<void> openSettings();

  /// Schedules the rest alert for [at], replacing any already pending.
  Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  });

  /// Withdraws the pending rest alert, if there is one.
  Future<void> cancel();
}

/// Does nothing; permission never granted. The provider's default, so tests
/// and any screen outside a real app run never touch the plugin.
class NoopRestAlertScheduler implements RestAlertScheduler {
  @override
  Future<bool> permissionGranted() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel() async {}
}

final restAlertSchedulerProvider = Provider<RestAlertScheduler>(
  (ref) => NoopRestAlertScheduler(),
);

/// The rest alert's on/off, and whether this phone has been asked for
/// notification permission for it.
///
/// On the phone rather than the account: it is about this device's
/// notifications. Every read and write is guarded -- a keystore that will not
/// answer costs the alert's settings, never the workout -- and an unreadable
/// "asked" reads as asked, so a broken keystore cannot become a prompt on
/// every rest.
class RestAlertStore {
  RestAlertStore({this._backing = const PluginSecureStore()});

  static const _enabledKey = 'rest_alert_enabled';
  static const _askedKey = 'rest_alert_asked';
  final SecureStore _backing;

  Future<bool> enabled() async {
    try {
      return await _backing.read(_enabledKey) != 'false';
    } catch (error) {
      debugPrint('Rest alert setting unreadable: $error');
      return true;
    }
  }

  Future<void> setEnabled(bool on) async {
    try {
      await _backing.write(_enabledKey, on ? 'true' : 'false');
    } catch (error) {
      debugPrint('Rest alert setting not saved: $error');
    }
  }

  Future<bool> asked() async {
    try {
      return await _backing.read(_askedKey) == 'true';
    } catch (error) {
      debugPrint('Rest alert prompt record unreadable: $error');
      return true;
    }
  }

  Future<void> markAsked() async {
    try {
      await _backing.write(_askedKey, 'true');
    } catch (error) {
      debugPrint('Rest alert prompt record not saved: $error');
    }
  }
}

final restAlertStoreProvider = Provider<RestAlertStore>(
  (ref) => RestAlertStore(),
);

/// Whether a rest that ends away from the screen sends a notification. The
/// switch in the rest sheet writes it; the logger reads it when the app goes
/// to the background.
class RestAlertEnabledController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(restAlertStoreProvider).enabled();

  Future<void> set(bool on) async {
    state = AsyncData(on);
    await ref.read(restAlertStoreProvider).setEnabled(on);
  }
}

final restAlertEnabledProvider =
    AsyncNotifierProvider<RestAlertEnabledController, bool>(
      RestAlertEnabledController.new,
    );
