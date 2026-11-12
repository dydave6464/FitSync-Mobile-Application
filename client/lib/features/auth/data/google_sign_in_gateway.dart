import 'package:google_sign_in/google_sign_in.dart';

/// How a Google sign-in attempt ended.
///
/// Three outcomes rather than a nullable token: "the user backed out" and
/// "Google could not sign them in" need different answers on screen -- the
/// first none at all, the second a message and another way in -- and a null
/// cannot tell them apart.
sealed class GoogleSignInResult {
  const GoogleSignInResult();
}

/// An ID token to hand to our own server.
final class GoogleSignInToken extends GoogleSignInResult {
  const GoogleSignInToken(this.idToken);

  final String idToken;
}

/// The user closed the account picker: a decision, not a failure.
final class GoogleSignInCancelled extends GoogleSignInResult {
  const GoogleSignInCancelled();
}

/// Google could not sign the user in: no Play Services, a dropped
/// connection, a misconfigured build. [cause] is kept for debugging only;
/// nothing shows it to the user.
final class GoogleSignInFailed extends GoogleSignInResult {
  const GoogleSignInFailed(this.cause);

  final Object cause;
}

/// The one thing the app needs from Google Sign-In: an ID token, or why
/// there is none.
///
/// Behind an interface because the plugin needs a platform channel and will
/// not run under `flutter test`.
abstract class GoogleSignInGateway {
  /// Never throws: every way the attempt can end is a [GoogleSignInResult].
  Future<GoogleSignInResult> signIn();
}

/// Written against google_sign_in 7.2.0, whose API differs substantially from
/// v6: a singleton with `initialize()` and `authenticate()` rather than
/// `GoogleSignIn().signIn()`, and cancellation raised as a
/// [GoogleSignInException] instead of returned as null.
class PluginGoogleSignInGateway implements GoogleSignInGateway {
  PluginGoogleSignInGateway({
    this.serverClientId = _defaultServerClientId,
    this.plugin,
  });

  /// The **web** OAuth client id, not the Android one.
  ///
  /// On Android the Android client only ties the package name and signing
  /// certificate to the project; it never appears as an audience. The ID
  /// token returned here is minted for `serverClientId`, and the server
  /// verifies `audience: GOOGLE_CLIENT_ID` — so the two must be the same web
  /// client id or every token is rejected as having the wrong audience.
  static const _defaultServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  final String serverClientId;

  /// Injectable for tests; the plugin's singleton otherwise. Read lazily so
  /// building the gateway never touches the platform.
  final GoogleSignIn? plugin;

  bool _initialized = false;

  @override
  Future<GoogleSignInResult> signIn() async {
    final signIn = plugin ?? GoogleSignIn.instance;

    try {
      if (!_initialized) {
        await signIn.initialize(
          serverClientId: serverClientId.isEmpty ? null : serverClientId,
        );
        // Only once it worked: a start that failed is tried again on the
        // next tap rather than left half-done for good.
        _initialized = true;
      }

      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      // An account was picked, so this is not a cancel. Without a token
      // (e.g. no GOOGLE_SERVER_CLIENT_ID in the build) there is nothing to
      // sign in with, and saying nothing would look like the button broke.
      if (idToken == null || idToken.isEmpty) {
        return GoogleSignInFailed(StateError('Google returned no ID token'));
      }
      return GoogleSignInToken(idToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const GoogleSignInCancelled();
      }
      return GoogleSignInFailed(error);
    } catch (error) {
      // A PlatformException from initialize(), or anything else the plugin
      // raises: still a failed attempt the screen must report.
      return GoogleSignInFailed(error);
    }
  }
}
