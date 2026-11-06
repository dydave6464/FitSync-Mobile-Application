import 'dart:math';

final _random = Random.secure();

/// A new random (version 4) UUID, such as
/// '3f1c2b9e-8d4a-4c1e-9b7a-2e5d6f708192': the key a save sends so that
/// sending it again (Try again after a lost answer) is not saved twice.
String newClientId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // the RFC 4122 variant
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
