import 'package:google_sign_in/google_sign_in.dart';

/// The one thing the app needs from Google Sign-In: an ID token to hand to
/// our own server, or null if the user backed out.
///
/// Behind an interface because the plugin needs a platform channel and will
/// not run under `flutter test`.
abstract class GoogleSignInGateway {
  /// Null means the user cancelled — a decision, not a failure.
  Future<String?> idToken();
}

/// Written against google_sign_in 7.2.0, whose API differs substantially from
/// v6: a singleton with `initialize()` and `authenticate()` rather than
/// `GoogleSignIn().signIn()`, and cancellation raised as a
/// [GoogleSignInException] instead of returned as null.
class PluginGoogleSignInGateway implements GoogleSignInGateway {
  PluginGoogleSignInGateway({this.serverClientId = _defaultServerClientId});

  /// The **web** OAuth client id, not the Android one.
  ///
  /// On Android the Android client only ties the package name and signing
  /// certificate to the project; it never appears as an audience. The ID
  /// token returned here is minted for `serverClientId`, and the server
  /// verifies `audience: GOOGLE_CLIENT_ID` — so the two must be the same web
  /// client id or every token is rejected as having the wrong audience.
  static const _defaultServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String serverClientId;

  bool _initialized = false;

  @override
  Future<String?> idToken() async {
    final signIn = GoogleSignIn.instance;

    if (!_initialized) {
      await signIn.initialize(
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      );
      _initialized = true;
    }

    try {
      final account = await signIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}
