import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/client_id.dart';

void main() {
  // NU-4: the key a single-food log sends, so a Try again never logs twice.
  test('newClientId is a version 4 UUID', () {
    final v4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    for (var i = 0; i < 100; i++) {
      expect(newClientId(), matches(v4));
    }
  });

  test('1,000 ids are all different', () {
    expect({for (var i = 0; i < 1000; i++) newClientId()}, hasLength(1000));
  });
}
