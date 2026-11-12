import '../../../core/api_client.dart';
import '../../../core/token_store.dart';
import '../../admin/domain/admin_user.dart';
import '../domain/auth_user.dart';
import '../domain/sign_in_outcome.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  // Every successful call through here persists the token before returning,
  // so a caller can never end up with a user object and no way to
  // authenticate. Registration does not use this path: there is no token to
  // write until the address is verified, and `data['token'] as String` would
  // throw trying to cast the missing value.
  //
  // The role is stored with the token, so a phone last used by an admin does
  // not open the admin tabs on a trainee's token.
  Future<AuthUser> _storeTrainee(Map<String, dynamic> data) async {
    await _tokens.write(data['token'] as String);
    await _tokens.writeRole('trainee');
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// The one sign-in that can let in an admin: the server looks in `admins`
  /// first and says which it found in `role`. Anything but `'admin'` is a
  /// trainee, including a server from before roles, which sends none.
  Future<SignInOutcome> login(String email, String password) async {
    final data = await _api.postJson('/api/v1/auth/login', {
      'email': email,
      'password': password,
    });
    if (data['role'] == 'admin') {
      await _tokens.write(data['token'] as String);
      await _tokens.writeRole('admin');
      return AdminSignedIn(
        AdminUser.fromJson(data['admin'] as Map<String, dynamic>),
      );
    }
    return TraineeSignedIn(await _storeTrainee(data));
  }

  /// The account is created, but cannot sign in until the address is
  /// verified — so there is no session to hand back, only confirmation that
  /// the request went through.
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _api.postJson('/api/v1/auth/register', {
      'email': email,
      'password': password,
      'fullName': fullName,
    });
  }

  /// Trainee-only: the server refuses an admin's email here.
  Future<AuthUser> signInWithGoogle(String idToken) async => _storeTrainee(
    await _api.postJson('/api/v1/auth/google', {'idToken': idToken}),
  );

  Future<AuthUser> me() async {
    final data = await _api.getJson('/api/v1/auth/me');
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> signOut() => _tokens.clear();

  /// Always answered with a 202, whatever the address, so it can never be
  /// used to learn who has an account. Callers must not turn a failure here
  /// into a different message than a success — see `ForgotPasswordScreen`.
  Future<void> requestPasswordReset(String email) async {
    await _api.postJson('/api/v1/auth/password-reset/request', {
      'email': email,
    });
  }

  /// Takes a password rather than a token: the account this resends to has
  /// never signed in, so there is no JWT yet to prove who is asking.
  Future<void> resendVerification({
    required String email,
    required String password,
  }) async {
    await _api.postJson('/api/v1/auth/verify-email/request', {
      'email': email,
      'password': password,
    });
  }

  /// The 6-digit code from the verification email. Signs nobody in: the
  /// caller signs in afterwards with the credentials it already holds. Any
  /// wrong, expired or used code is `ApiException('CODE_INVALID')`.
  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    await _api.postJson('/api/v1/auth/verify-email', {
      'email': email,
      'code': code,
    });
  }

  /// Sets a new password with the 6-digit code from the reset email. Signs
  /// nobody in, as [verifyEmail]. A too-short password is refused before the
  /// code is looked at, so it costs no attempt.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    await _api.postJson('/api/v1/auth/password-reset', {
      'email': email,
      'code': code,
      'password': password,
    });
  }

  /// Changes the password of the signed-in account. The server signs every
  /// other device out and answers with a fresh token for this one, stored
  /// here before returning: the old token stops working with the change. A
  /// wrong [currentPassword] is `ApiException('WRONG_PASSWORD')`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final data = await _api.postJson('/api/v1/auth/password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
    await _tokens.write(data['token'] as String);
    await _tokens.writeRole('trainee');
  }

  /// Deletes the signed-in account and everything in it, confirmed with the
  /// account's [password] or a fresh Google [idToken] (exactly one). The
  /// local clean-up afterwards is `AuthController.onAccountDeleted`'s.
  Future<void> deleteAccount({String? password, String? idToken}) async {
    assert(
      (password == null) != (idToken == null),
      'Confirm with a password or a Google token, not both or neither.',
    );
    await _api.postJson('/api/v1/account/delete', {
      'password': ?password,
      'idToken': ?idToken,
    });
  }
}
