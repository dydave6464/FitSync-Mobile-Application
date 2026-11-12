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

  test('round-trips the signed-in role', () async {
    final store = TokenStore(backing: InMemorySecureStore());
    await store.writeRole('admin');
    expect(await store.readRole(), 'admin');
  });

  test('a fresh store has no role, which callers read as trainee', () async {
    // An install from before roles keeps a token and no role: it must go on
    // opening the trainee app.
    final store = TokenStore(backing: InMemorySecureStore());
    expect(await store.readRole(), isNull);
  });

  test('keeps the role under its own key, next to the token', () async {
    final backing = InMemorySecureStore();
    final store = TokenStore(backing: backing);
    await store.write('tok');
    await store.writeRole('admin');
    expect(await backing.read('fitsync.role'), 'admin');
    expect(await backing.read('fitsync.jwt'), 'tok');
  });

  test('clear removes the role as well as the token', () async {
    final store = TokenStore(backing: InMemorySecureStore());
    await store.write('abc.def.ghi');
    await store.writeRole('admin');
    await store.clear();
    expect(await store.read(), isNull);
    expect(
      await store.readRole(),
      isNull,
      reason: "the next sign-in must not inherit an admin's role",
    );
  });
}
