import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/manila_day.dart';
import '../../../core/token_store.dart' show PluginSecureStore, SecureStore;
import '../domain/activity.dart' show manilaMidnight;
import '../domain/step_readings.dart';

/// The phone's step counter. Behind an interface, like ReminderScheduler, so
/// tests never touch the platform channel: `main.dart` overrides the no-op
/// default with the platform's implementation.
abstract interface class StepSource {
  /// Steps since Manila midnight on [now]'s day. On iPhone this may throw a
  /// [PlatformException] (e.g. Motion & Fitness refused).
  Future<DaySteps> today(DateTime now);

  /// Steps for each of the six Manila days before today, keyed
  /// `YYYY-MM-DD`; empty where the phone keeps no history (Android). On
  /// iPhone this may throw a [PlatformException], as [today] may.
  Future<Map<String, int>> earlierDays(DateTime now);

  /// Today's running total while listened to.
  Stream<int> live(DateTime now);
}

class NoStepSource implements StepSource {
  const NoStepSource();

  @override
  Future<DaySteps> today(DateTime now) async => const DaySteps(steps: 0);

  @override
  Future<Map<String, int>> earlierDays(DateTime now) async => const {};

  @override
  Stream<int> live(DateTime now) => const Stream.empty();
}

const _methodChannel = MethodChannel('fitsync/steps');
const _liveChannel = EventChannel('fitsync/steps/live');
const _day = Duration(days: 1);

/// Core Motion answers "steps between two times" for the last seven days.
class IosStepSource implements StepSource {
  IosStepSource({this._methods = _methodChannel, this._events = _liveChannel});

  final MethodChannel _methods;
  final EventChannel _events;

  Future<int> _between(DateTime from, DateTime to) async =>
      await _methods.invokeMethod<int>('stepsBetween', {
        'fromMs': from.millisecondsSinceEpoch,
        'toMs': to.millisecondsSinceEpoch,
      }) ??
      0;

  @override
  Future<DaySteps> today(DateTime now) async =>
      DaySteps(steps: await _between(manilaMidnight(now), now));

  @override
  Future<Map<String, int>> earlierDays(DateTime now) async {
    final midnight = manilaMidnight(now);
    return {
      for (var back = 1; back <= 6; back++)
        manilaDayOf(midnight.subtract(_day * back)): await _between(
          midnight.subtract(_day * back),
          midnight.subtract(_day * (back - 1)),
        ),
    };
  }

  @override
  Stream<int> live(DateTime now) => _events
      .receiveBroadcastStream({
        'fromMs': manilaMidnight(now).millisecondsSinceEpoch,
      })
      .map((event) => event as int);
}

/// Android's sensor gives a total since the last restart; the day is worked
/// out from readings kept on the phone (domain/step_readings.dart).
class AndroidStepSource implements StepSource {
  AndroidStepSource({
    this._store = const PluginSecureStore(),
    this._methods = _methodChannel,
    this._events = _liveChannel,
  });

  static const _key = 'step_readings';
  final SecureStore _store;
  final MethodChannel _methods;
  final EventChannel _events;

  static StepReading _fromChannel(Object? raw) {
    final map = (raw as Map<Object?, Object?>).cast<String, dynamic>();
    return StepReading.fromJson(map);
  }

  Future<List<StepReading>> _load() async {
    final raw = await _store.read(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((r) => StepReading.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<DaySteps> today(DateTime now) async {
    final midnight = manilaMidnight(now).millisecondsSinceEpoch;
    final readings = await _load();
    try {
      readings.add(_fromChannel(await _methods.invokeMethod('readStepCounter')));
    } on PlatformException {
      // No reading this time (a timeout, or no permission): count from
      // the ones already kept.
    }
    final kept = pruneReadings(readings, midnight);
    await _store.write(_key, jsonEncode([for (final r in kept) r.toJson()]));
    return stepsSince(kept, midnight);
  }

  @override
  Future<Map<String, int>> earlierDays(DateTime now) async => const {};

  @override
  Stream<int> live(DateTime now) async* {
    final midnight = manilaMidnight(now).millisecondsSinceEpoch;
    final saved = pruneReadings(await _load(), midnight);
    await for (final event in _events.receiveBroadcastStream()) {
      yield stepsSince([...saved, _fromChannel(event)], midnight).steps;
    }
  }
}
