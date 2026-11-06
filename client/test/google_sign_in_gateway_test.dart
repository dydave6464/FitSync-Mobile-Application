import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:fitsync/features/auth/data/google_sign_in_gateway.dart';

/// Stands in for the plugin's singleton, which needs a platform channel.
class _FakeGoogleSignIn implements GoogleSignIn {
  _FakeGoogleSignIn({this.onInitialize, required this.onAuthenticate});

  final Future<void> Function()? onInitialize;
  final Future<GoogleSignInAccount> Function() onAuthenticate;
  int initializeCalls = 0;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {
    initializeCalls++;
    await onInitialize?.call();
  }

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const <String>[],
  }) => onAuthenticate();

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

class _FakeAccount implements GoogleSignInAccount {
  _FakeAccount(this.idToken);

  final String? idToken;

  @override
  GoogleSignInAuthentication get authentication =>
      GoogleSignInAuthentication(idToken: idToken);

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

PluginGoogleSignInGateway _gateway(_FakeGoogleSignIn plugin) =>
    PluginGoogleSignInGateway(serverClientId: 'web-client', plugin: plugin);

void main() {
  test('a picked account with a token is a token', () async {
    final result = await _gateway(
      _FakeGoogleSignIn(onAuthenticate: () async => _FakeAccount('tok')),
    ).signIn();

    expect(result, isA<GoogleSignInToken>());
    expect((result as GoogleSignInToken).idToken, 'tok');
  });

  test('a closed dialog is a cancel, not a failure', () async {
    final result = await _gateway(
      _FakeGoogleSignIn(
        onAuthenticate: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      ),
    ).signIn();

    expect(result, isA<GoogleSignInCancelled>());
  });

  test('any other Google error is a failure', () async {
    final result = await _gateway(
      _FakeGoogleSignIn(
        onAuthenticate: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      ),
    ).signIn();

    expect(result, isA<GoogleSignInFailed>());
  });

  test('an account picked but no token is a failure, not a cancel', () async {
    // What a build missing GOOGLE_SERVER_CLIENT_ID gets back.
    final result = await _gateway(
      _FakeGoogleSignIn(onAuthenticate: () async => _FakeAccount(null)),
    ).signIn();

    expect(result, isA<GoogleSignInFailed>());
  });

  test('a plugin that cannot start is a failure, and is tried again next '
      'time', () async {
    var failInit = true;
    final plugin = _FakeGoogleSignIn(
      onInitialize: () async {
        if (failInit) throw PlatformException(code: 'no_play_services');
      },
      onAuthenticate: () async => _FakeAccount('tok'),
    );
    final gateway = _gateway(plugin);

    expect(await gateway.signIn(), isA<GoogleSignInFailed>());

    failInit = false;
    expect(await gateway.signIn(), isA<GoogleSignInToken>());
    expect(plugin.initializeCalls, 2);
  });
}
