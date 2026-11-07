import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'ad_form_screen.dart';
import 'providers.dart';
import 'widgets/admin_widgets.dart';

/// Opens the ad form: a new ad when [ad] is null. Pushed over the tabs, so
/// the form has the whole screen and back returns to the list.
Future<void> openAdForm(BuildContext context, {AdminAd? ad}) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => AdFormScreen(ad: ad)));

/// The Content tab's Ads segment: every ad, newest first, with how it is
/// doing. A row opens the ad form; the Content app bar's + adds one.
class AdsTab extends ConsumerWidget {
  const AdsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(adminRepositoryProvider).baseUrl;

    return ref
        .watch(adminAdsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => FsRetry(
            fullScreen: true,
            message: userMessage(error),
            buttonKey: const Key('admin.ads.retry'),
            onRetry: () => ref.invalidate(adminAdsProvider),
          ),
          data: (ads) => RefreshIndicator(
            onRefresh: () => ref.refresh(adminAdsProvider.future),
            child: ads.isEmpty
                ? ListView(
                    children: [
                      AdminEmpty(
                        message: 'No ads yet.',
                        actionLabel: 'New ad',
                        actionKey: const Key('admin.ads.new'),
                        onAction: () => openAdForm(context),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: ads.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _AdRow(
                        key: ValueKey('admin.ad.${ads[i].id}'),
                        ad: ads[i],
                        baseUrl: baseUrl,
                        onTap: () => openAdForm(context, ad: ads[i]),
                      ),
                    ),
                  ),
          ),
        );
  }
}

/// The status in its word, first match wins on the server: Paused,
/// Scheduled, Ended, else Running.
String adStatusWord(String status) => switch (status) {
  'paused' => 'Paused',
  'scheduled' => 'Scheduled',
  'ended' => 'Ended',
  _ => 'Running',
};

/// "Running" in the accent, "Ended" dim, and "Scheduled" and "Paused" with
/// a blue or amber dot: as words, blue and amber are too faint on the light
/// theme's tag (the Pending tag's rule). The word is always there, so the
/// colour is never the only clue.
class AdStatusTag extends StatelessWidget {
  const AdStatusTag(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final word = adStatusWord(status);
    return switch (status) {
      'paused' => StatusTag(word, dot: t.amber),
      'scheduled' => StatusTag(word, dot: t.blue),
      'ended' => StatusTag(word, color: t.text3),
      _ => StatusTag(word, color: t.accentText),
    };
  }
}

class _AdRow extends StatelessWidget {
  const _AdRow({
    super.key,
    required this.ad,
    required this.baseUrl,
    required this.onTap,
  });

  final AdminAd ad;
  final String baseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final run = '${ad.advertiser} · ${runLabel(ad.startsOn, ad.endsOn)}';
    final counts = adCountsLabel(ad.views, ad.taps);
    final spoken = [ad.title, run, counts, adStatusWord(ad.status)].join(', ');
    // At large text the tag beside the lines would squeeze them to a letter
    // a line on a narrow phone, so it moves under them.
    final tagBelow = MediaQuery.textScalerOf(context).scale(10) > 13;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FsCard(
        small: true,
        onTap: onTap,
        child: Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Row(
            children: [
              _Thumb(
                imageKey: ValueKey('admin.ad.${ad.id}.image'),
                url: mediaUrl(baseUrl, ad.imageUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    Text(run, style: TextStyle(fontSize: 12, color: t.text2)),
                    Text(
                      counts,
                      style: TextStyle(fontSize: 11, color: t.text3),
                    ),
                    if (tagBelow) ...[
                      const SizedBox(height: 4),
                      AdStatusTag(ad.status),
                    ],
                  ],
                ),
              ),
              if (!tagBelow) ...[
                const SizedBox(width: 8),
                AdStatusTag(ad.status),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The ad's picture at 64 x 36 (16:9); a plain image icon while it loads or
/// when it cannot.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.imageKey, required this.url});

  final Key imageKey;
  final String url;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final placeholder = Icon(Icons.image_outlined, size: 18, color: t.text3);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: t.surface2,
        child: SizedBox(
          width: 64,
          height: 36,
          child: Image.network(
            url,
            key: imageKey,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : Center(child: placeholder),
            errorBuilder: (_, _, _) => Center(child: placeholder),
          ),
        ),
      ),
    );
  }
}
