import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/core/token_store.dart';

void main() {
  test('round-trips a token', () async {
    final store = TokenStore(backing: InMemorySecureStore());
    expect(await store.read(), isNull);
    await store.write('abc.def.ghi');
    expect(await store.read(), 'abc.def.ghi');
  });

  test('clear removes the token', () async {
    final store = TokenStore(backing: InMemorySecureStore());
    await store.write('abc.def.ghi');
    await store.clear();
    expect(await store.read(), isNull);
  });
}
