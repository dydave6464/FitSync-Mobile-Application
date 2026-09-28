import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../core/token_store.dart' show PluginSecureStore, SecureStore;

/// Where step counting stands. `refused` covers every "no": the OS prompt
/// declined, permanently denied, or Fitness Tracking switched off.
enum StepAccess { notAsked, granted, refused }

abstract interface class StepPermission {
  Future<StepAccess> status();

  /// Shows the OS prompt when the OS still can; returns the outcome.
  Future<StepAccess> request();

  Future<void> openSettings();
}

class NoStepPermission implements StepPermission {
  const NoStepPermission();

  @override
  Future<StepAccess> status() async => StepAccess.notAsked;

  @override
  Future<StepAccess> request() async => StepAccess.refused;

  @override
  Future<void> openSettings() async {}
}

/// Motion & Fitness on iPhone (permission_handler's `sensors`), Physical
/// activity on Android (`activityRecognition`) -- never the other way round:
/// `sensors` on Android is BODY_SENSORS. Neither OS can tell "never asked"
/// from "refused" reliably, so the app remembers that it asked.
class DeviceStepPermission implements StepPermission {
  DeviceStepPermission({
    this._store = const PluginSecureStore(),
    Future<bool> Function()? isGranted,
    Future<bool> Function()? requestGrant,
    Future<void> Function()? openSettings,
  }) : _isGranted = isGranted ?? (() async => (await _permission.status).isGranted),
       _requestGrant = requestGrant ?? (() async => (await _permission.request()).isGranted),
       _openSettings = openSettings ?? (() async {
         await ph.openAppSettings();
       });

  static const _askedKey = 'step_permission_asked';

  static ph.Permission get _permission =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? ph.Permission.sensors
      : ph.Permission.activityRecognition;

  final SecureStore _store;
  final Future<bool> Function() _isGranted;
  final Future<bool> Function() _requestGrant;
  final Future<void> Function() _openSettings;

  @override
  Future<StepAccess> status() async {
    if (await _isGranted()) return StepAccess.granted;
    return await _store.read(_askedKey) == 'true'
        ? StepAccess.refused
        : StepAccess.notAsked;
  }

  @override
  Future<StepAccess> request() async {
    await _store.write(_askedKey, 'true');
    return await _requestGrant() ? StepAccess.granted : StepAccess.refused;
  }

  @override
  Future<void> openSettings() => _openSettings();
}
