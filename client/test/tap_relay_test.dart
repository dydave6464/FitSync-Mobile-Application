import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/reminders/data/tap_relay.dart';

void main() {
  test('two listeners on the same stream both receive a later tap', () async {
    final relay = TapRelay();
    final first = <String>[];
    final second = <String>[];
    relay.stream.listen(first.add);
    relay.stream.listen(second.add);

    relay.add('routine');
    await Future<void>.delayed(Duration.zero);

    expect(first, ['routine']);
    expect(second, ['routine']);
  });

  test('a launch payload reaches the first listener exactly once', () async {
    final relay = TapRelay(launchPayload: 'recovery');
    final first = <String>[];
    relay.stream.listen(first.add);
    await Future<void>.delayed(Duration.zero);

    expect(first, ['recovery']);

    final second = <String>[];
    relay.stream.listen(second.add);
    await Future<void>.delayed(Duration.zero);

    expect(
      second,
      isEmpty,
      reason: 'a later listener must not replay the launch payload',
    );
  });

  test(
    'with no launch payload, a first listener sees only later taps',
    () async {
      final relay = TapRelay();
      final first = <String>[];
      relay.stream.listen(first.add);
      await Future<void>.delayed(Duration.zero);

      expect(first, isEmpty);

      relay.add('routine');
      await Future<void>.delayed(Duration.zero);

      expect(first, ['routine']);
    },
  );
}
