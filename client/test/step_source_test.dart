import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/activity/data/step_source.dart';

const _methods = MethodChannel('fitsync/steps');
const _hour = 3_600_000;
// 2026-09-28 10:00 Manila; Manila midnight is 2026-09-27 16:00 UTC.
final _now = DateTime.utc(2026, 9, 28, 2);
final _midnightMs = DateTime.utc(2026, 9, 27, 16).millisecondsSinceEpoch;
const _boot = 900_000_000_000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(_methods, null));

  group('AndroidStepSource', () {
    test('today reads the sensor, keeps the reading, and counts from before midnight', () async {
      final store = InMemorySecureStore();
      await store.write('step_readings', jsonEncode([
        {'atMs': _midnightMs - 2 * _hour, 'steps': 5000, 'bootMs': _boot},
      ]));
      messenger.setMockMethodCallHandler(_methods, (call) async {
        expect(call.method, 'readStepCounter');
        return {'steps': 5800, 'bootMs': _boot, 'atMs': _midnightMs + 10 * _hour};
      });

      final day = await AndroidStepSource(store: store).today(_now);

      expect(day.steps, 800);
      expect(day.sinceTurnedOn, isFalse);
      final kept = jsonDecode((await store.read('step_readings'))!) as List;
      expect(kept, hasLength(2));
    });

    test('a sensor timeout falls back to the saved readings', () async {
      final store = InMemorySecureStore();
      await store.write('step_readings', jsonEncode([
        {'atMs': _midnightMs - 2 * _hour, 'steps': 5000, 'bootMs': _boot},
        {'atMs': _midnightMs + _hour, 'steps': 5300, 'bootMs': _boot},
      ]));
      messenger.setMockMethodCallHandler(_methods, (call) async {
        throw PlatformException(code: 'timeout');
      });

      final day = await AndroidStepSource(store: store).today(_now);

      expect(day.steps, 300);
    });

    test('has no earlier days: Android keeps no history', () async {
      expect(await AndroidStepSource(store: InMemorySecureStore()).earlierDays(_now), isEmpty);
    });
  });

  group('IosStepSource', () {
    test('today asks Core Motion for midnight to now', () async {
      final calls = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(_methods, (call) async {
        calls.add(call.arguments as Map<Object?, Object?>);
        return 6420;
      });

      final day = await IosStepSource().today(_now);

      expect(day.steps, 6420);
      expect(calls.single['fromMs'], _midnightMs);
      expect(calls.single['toMs'], _now.millisecondsSinceEpoch);
    });

    test('earlierDays asks for each of the six days before today', () async {
      final calls = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(_methods, (call) async {
        calls.add(call.arguments as Map<Object?, Object?>);
        return 1000 * calls.length;
      });

      final days = await IosStepSource().earlierDays(_now);

      expect(days, {
        '2026-09-27': 1000, '2026-09-26': 2000, '2026-09-25': 3000,
        '2026-09-24': 4000, '2026-09-23': 5000, '2026-09-22': 6000,
      });
      expect(calls.first['fromMs'], _midnightMs - 24 * _hour);
      expect(calls.first['toMs'], _midnightMs);
    });
  });
}
