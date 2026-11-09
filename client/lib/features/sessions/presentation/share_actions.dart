import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the share sheet does outside the app: the phone's share menu, and
/// the browser. Behind a provider so widget tests swap in a fake instead of
/// reaching a platform channel.
class ShareActions {
  const ShareActions({required this.share, required this.open});

  /// Opens the share menu with [text]. False when the menu could not open,
  /// so the caller can fall back to copying. A user who opens it and backs
  /// out has not failed: that is still true.
  final Future<bool> Function(String text) share;

  /// Opens [url] outside the app. False when nothing could open it.
  final Future<bool> Function(Uri url) open;
}

final shareActionsProvider = Provider<ShareActions>(
  (ref) => ShareActions(
    share: (text) async {
      // A platform error (no share activity, a plugin failure) is the menu
      // failing to open too: false, so the caller copies instead.
      try {
        final result = await SharePlus.instance.share(ShareParams(text: text));
        return result.status != ShareResultStatus.unavailable;
      } catch (_) {
        return false;
      }
    },
    open: (url) async {
      try {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    },
  ),
);
