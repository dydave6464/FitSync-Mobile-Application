import '../../../core/api_client.dart';
import '../../../core/token_store.dart';
import '../domain/auth_user.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  // Every successful call through here persists the token before returning,
  // so a caller can never end up with a user object and no way to
  // authenticate. Registration does not use this path: there is no token to
  // write until the address is verified, and `data['token'] as String` would
  // throw trying to cast the missing value.
  Future<AuthUser> _authenticate(String path, Map<String, dynamic> body) async {
    final data = await _api.postJson(path, body);
    await _tokens.write(data['token'] as String);
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AuthUser> login(String email, String password) =>
      _authenticate('/api/v1/auth/login', {'email': email, 'password': password});

  /// The account is created, but cannot sign in until the address is
  /// verified — so there is no session to hand back, only confirmation that
  /// the request went through.
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _api.postJson('/api/v1/auth/register',
        {'email': email, 'password': password, 'fullName': fullName});
  }

  Future<AuthUser> signInWithGoogle(String idToken) =>
      _authenticate('/api/v1/auth/google', {'idToken': idToken});

  Future<AuthUser> me() async {
    final data = await _api.getJson('/api/v1/auth/me');
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> signOut() => _tokens.clear();

  /// Always answered with a 202, whatever the address, so it can never be
  /// used to learn who has an account. Callers must not turn a failure here
  /// into a different message than a success — see `ForgotPasswordScreen`.
  Future<void> requestPasswordReset(String email) async {
    await _api.postJson('/api/v1/auth/password-reset/request', {'email': email});
  }

  /// Takes a password rather than a token: the account this resends to has
  /// never signed in, so there is no JWT yet to prove who is asking.
  Future<void> resendVerification({
    required String email,
    required String password,
  }) async {
    await _api.postJson('/api/v1/auth/verify-email/request',
        {'email': email, 'password': password});
  }
}
