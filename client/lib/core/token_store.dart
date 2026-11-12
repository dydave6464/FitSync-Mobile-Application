import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the FitSync JWT lives.
///
/// Behind an interface so tests never touch the platform channel — the real
/// plugin needs a running Android or iOS host and would make every widget
/// test require a device.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PluginSecureStore implements SecureStore {
  const PluginSecureStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemorySecureStore implements SecureStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class TokenStore {
  TokenStore({this._backing = const PluginSecureStore()});

  static const _key = 'fitsync.jwt';
  static const _roleKey = 'fitsync.role';
  final SecureStore _backing;

  Future<String?> read() => _backing.read(_key);
  Future<void> write(String token) => _backing.write(_key, token);

  /// Who the stored token belongs to: `'trainee'` or `'admin'`. Null on an
  /// install from before roles, which callers read as a trainee, so those
  /// keep opening the trainee app.
  Future<String?> readRole() => _backing.read(_roleKey);
  Future<void> writeRole(String role) => _backing.write(_roleKey, role);

  /// Drops the role with the token, so the next sign-in starts from neither.
  Future<void> clear() async {
    await _backing.delete(_key);
    await _backing.delete(_roleKey);
  }
}
