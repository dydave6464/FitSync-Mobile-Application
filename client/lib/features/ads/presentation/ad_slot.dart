import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../pro/presentation/pro_screen.dart' show openProScreen;
import '../../profile/presentation/providers.dart' show profileProvider;
import '../data/ad_source.dart';
import '../domain/house_ad.dart';

/// Opens an ad's link in the browser, outside the app. A provider so tests
/// can see what would open without a browser.
final adLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The ad for the slots on screen, asked for once each time a slot first
/// shows. Never retried: a missing ad costs nothing, and asking again is
/// not worth the trainee's data.
final currentAdProvider = FutureProvider.autoDispose<HouseAd?>(
  (ref) => ref.watch(adSourceProvider).current(),
  retry: (_, _) => null,
);

/// A small ad card for free trainees, in calm spots only: the bottom of
/// Home and of Nutrition, never a workout or the logger.
///
/// Nothing at all is drawn for a Pro member, while the profile or the ad is
/// on its way, when no ad is running, or when anything fails: an ad never
/// shows an error or a spinner.
class AdSlot extends ConsumerWidget {
  const AdSlot({super.key, required this.placement});

  /// Where the slot sits: `home` or `nutrition`. Not sent today; an ad
  /// network behind [AdSource] may want it later.
  final String placement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only once the profile says free: a Pro member's slot never asks for an
    // ad, not even while the profile loads.
    final profile = ref.watch(profileProvider).value;
    if (profile == null || profile.isPremium) return const SizedBox.shrink();
    return ref
        .watch(currentAdProvider)
        .when(
          data: (ad) => ad == null
              ? const SizedBox.shrink()
              // Keyed by the ad, so a different ad is a new card that
              // reports its own view.
              : _AdCard(key: ValueKey(ad.id), ad: ad),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        );
  }
}

class _AdCard extends ConsumerStatefulWidget {
  const _AdCard({super.key, required this.ad});

  final HouseAd ad;

  @override
  ConsumerState<_AdCard> createState() => _AdCardState();
}

class _AdCardState extends ConsumerState<_AdCard> {
  @override
  void initState() {
    super.initState();
    // Once per card: a rebuild (a theme or text size change, a scroll back
    // into view of a kept card) is not another view.
    unawaited(ref.read(adSourceProvider).viewed(widget.ad.id));
  }

  Future<void> _open(Uri link) async {
    // The tap is counted first, but not waited for: the page opens at once
    // even on a slow connection.
    unawaited(ref.read(adSourceProvider).tapped(widget.ad.id));
    try {
      await ref.read(adLinkOpenerProvider)(link);
    } catch (_) {
      // No browser to open it: an ad never shows an error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final ad = widget.ad;
    final link = switch (ad.linkUrl) {
      final url? => Uri.tryParse(url),
      null => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FsCard(
          small: true,
          onTap: link == null ? null : () => _open(link),
          // The prototype's compact row: a small square image, the title
          // beside it, the "Ad" label, and a chevron when it opens a page.
          child: Row(
            children: [
              Image.network(
                ad.imageUrl,
                key: const Key('ad.image'),
                fit: BoxFit.cover,
                // The title beside it says what the ad is, loaded image or
                // not: an image's label is lost when it fails to load.
                excludeFromSemantics: true,
                // The frame, gap included, is drawn only round a loaded
                // image: one that fails leaves the title on its own.
                frameBuilder: (context, child, frame, sync) => Padding(
                  key: const Key('ad.thumb'),
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FsRadius.sm),
                    child: SizedBox.square(dimension: 52, child: child),
                  ),
                ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              Expanded(
                child: Text(
                  ad.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const FsTag('Ad'),
              if (link != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: t.text3),
              ],
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const Key('ad.removeWithPro'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => openProScreen(context),
            child: const Text('Remove ads with Pro'),
          ),
        ),
      ],
    );
  }
}
