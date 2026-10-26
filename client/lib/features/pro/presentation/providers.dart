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
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.inAppBrowserView),
);
