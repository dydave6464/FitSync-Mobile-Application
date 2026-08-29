import '../../../core/api_client.dart';
import '../../../core/token_store.dart';
import '../domain/auth_user.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  // Every successful entry point persists the token before returning, so a
  // caller can never end up with a user object and no way to authenticate.
  Future<AuthUser> _authenticate(String path, Map<String, dynamic> body) async {
    final data = await _api.postJson(path, body);
    await _tokens.write(data['token'] as String);
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AuthUser> login(String email, String password) =>
      _authenticate('/api/v1/auth/login', {'email': email, 'password': password});

  Future<AuthUser> register({
    required String email,
    required String password,
    required String fullName,
  }) =>
      _authenticate('/api/v1/auth/register',
          {'email': email, 'password': password, 'fullName': fullName});

  Future<AuthUser> signInWithGoogle(String idToken) =>
      _authenticate('/api/v1/auth/google', {'idToken': idToken});

  Future<AuthUser> me() async {
    final data = await _api.getJson('/api/v1/auth/me');
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> signOut() => _tokens.clear();
}
