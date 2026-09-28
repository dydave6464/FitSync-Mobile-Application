import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// Motion & Fitness on iPhone, asked through the app's own step plugin
/// (`fitsync/steps` in AppDelegate.swift): Core Motion knows whether it has
/// asked, so there is no "asked" flag there. Not permission_handler's
/// `sensors`: under Swift Package Manager it compiles that permission out
/// when the build cannot find Info.plist (e.g. a build started from
/// Xcode.app), and then answers denied without ever prompting.
///
/// Physical activity on Android, through permission_handler's
/// `activityRecognition` -- not `sensors`, which on Android is BODY_SENSORS.
/// Android cannot tell "never asked" from "refused" reliably, so the app
/// remembers that it asked.
class DeviceStepPermission implements StepPermission {
  DeviceStepPermission({
    this._store = const PluginSecureStore(),
    Future<bool> Function()? isGranted,
    Future<bool> Function()? requestGrant,
    Future<void> Function()? openSettings,
    bool? ios,
    this._methods = const MethodChannel('fitsync/steps'),
  }) : _ios = ios ?? defaultTargetPlatform == TargetPlatform.iOS,
       _isGranted = isGranted ?? (() async => (await _permission.status).isGranted),
       _requestGrant = requestGrant ?? (() async => (await _permission.request()).isGranted),
       _openSettings = openSettings ?? (() async {
         await ph.openAppSettings();
       });

  static const _askedKey = 'step_permission_asked';

  static const _permission = ph.Permission.activityRecognition;

  final SecureStore _store;
  final bool _ios;
  final MethodChannel _methods;
  final Future<bool> Function() _isGranted;
  final Future<bool> Function() _requestGrant;
  final Future<void> Function() _openSettings;

  /// Core Motion's authorization: "granted", "denied", "restricted" or
  /// "notDetermined". A platform error counts as a no.
  Future<String?> _ask(String method) async {
    try {
      return await _methods.invokeMethod<String>(method);
    } on PlatformException {
      return 'denied';
    }
  }

  @override
  Future<StepAccess> status() async {
    if (_ios) {
      return switch (await _ask('authorizationStatus')) {
        'granted' => StepAccess.granted,
        'notDetermined' => StepAccess.notAsked,
        _ => StepAccess.refused,
      };
    }
    if (await _isGranted()) return StepAccess.granted;
    return await _store.read(_askedKey) == 'true'
        ? StepAccess.refused
        : StepAccess.notAsked;
  }

  @override
  Future<StepAccess> request() async {
    if (_ios) {
      // Still notDetermined after asking means no answer: treat it as a no.
      return await _ask('requestAuthorization') == 'granted'
          ? StepAccess.granted
          : StepAccess.refused;
    }
    await _store.write(_askedKey, 'true');
    return await _requestGrant() ? StepAccess.granted : StepAccess.refused;
  }

  @override
  Future<void> openSettings() => _openSettings();
}
