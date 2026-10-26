import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../exercises/presentation/providers.dart' show apiClientProvider;
import '../data/pro_repository.dart';
import '../domain/pro_status.dart';

final proRepositoryProvider = Provider<ProRepository>(
  (ref) => ProRepository(ref.watch(apiClientProvider)),
);

/// No automatic retry: the Pro screen has its own Try again, and a test with
/// no server must not be left with a retry timer pending.
final proStatusProvider = FutureProvider.autoDispose<ProStatus>(
  (ref) => ref.watch(proRepositoryProvider).status(),
  retry: (count, error) => null,
);

/// Opens PayMongo's page in a browser sheet over the app (SFSafariViewController
/// / Chrome Custom Tab). Injectable for tests, which have no browser.
final proCheckoutOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.inAppBrowserView),
);

/// The latest checkout the Pro screen made that it has not yet seen paid.
///
/// Kept outside the screen so that a payment finished after the screen closed
/// (closed before the next check, or a check that failed on a weak signal) is
/// still confirmed the next time the screen opens. It lives in memory only:
/// if the phone kills the app, the server has to find the payment instead.
/// It belongs to one account, so sign-out clears it (AuthController).
class ProPendingCheckout extends Notifier<ProCheckout?> {
  @override
  ProCheckout? build() => null;

  void remember(ProCheckout checkout) => state = checkout;

  /// Forgets [paymentId] once nothing more can come of it: it was paid, its
  /// page never opened, or the server does not know it (404, 409). A newer
  /// checkout stays.
  void forget(int paymentId) {
    if (state?.paymentId == paymentId) state = null;
  }
}

final proPendingCheckoutProvider =
    NotifierProvider<ProPendingCheckout, ProCheckout?>(ProPendingCheckout.new);
