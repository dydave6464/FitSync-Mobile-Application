import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/ads/data/ad_source.dart';
import 'package:fitsync/features/ads/domain/house_ad.dart';
import 'package:fitsync/features/ads/presentation/ad_slot.dart';
import 'package:fitsync/features/pro/presentation/pro_screen.dart';
import 'package:fitsync/features/pro/presentation/providers.dart'
    show proRepositoryProvider;
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'helpers/fake_ad_source.dart';
import 'helpers/fake_image_http.dart';
import 'helpers/fake_pro_repository.dart';

/// The profile arrives a moment later, as it does from the server, so a
/// slot that asked for an ad before knowing who is signed in is caught.
class _StubProfile extends ProfileNotifier {
  _StubProfile(this.premium);

  final bool premium;

  @override
  Future<Profile> build() async => Profile(
    userId: 1,
    email: 'juan@example.com',
    fullName: 'Juan Dela Cruz',
    onboardingCompleted: true,
    isPremium: premium,
    notificationsEnabled: true,
    equipment: const [],
    injuries: const [],
  );
}

/// Pumps one slot in a list, as Home and Nutrition hold it. Returns the
/// log the source and the link opener write to, in order.
Future<List<String>> _pump(
  WidgetTester tester,
  FakeAdSource source, {
  bool premium = false,
  bool dark = false,
  double textScale = 1,
}) async {
  final log = source.calls;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(() => _StubProfile(premium)),
        adSourceProvider.overrideWithValue(source),
        adLinkOpenerProvider.overrideWithValue((uri) async {
          log.add('open $uri');
          return true;
        }),
        proRepositoryProvider.overrideWithValue(FakeProRepository()),
      ],
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: const [AdSlot(placement: 'home')],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return log;
}

const _otherAd = HouseAd(
  id: 8,
  title: 'Whey protein, buy 1 take 1',
  imageUrl: 'http://fitsync.test/storage/ads/8.jpg',
  linkUrl: null,
);

/// [slots] at the top of a list far taller than the screen, so a scroll
/// takes them off it (and disposes them) and back.
Future<void> _pumpLong(
  WidgetTester tester,
  FakeAdSource source,
  List<Widget> slots,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(() => _StubProfile(false)),
        adSourceProvider.overrideWithValue(source),
        proRepositoryProvider.overrideWithValue(FakeProRepository()),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [...slots, const SizedBox(height: 4000)],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a free trainee sees the card: the Ad label, image and title', (
    tester,
  ) async {
    await _pump(tester, FakeAdSource(ad: sampleHouseAd));

    expect(find.byType(FsCard), findsOneWidget);
    expect(
      find.descendant(of: find.byType(FsTag), matching: find.text('Ad')),
      findsOneWidget,
    );
    expect(find.text('GymShark PH: 20% off'), findsOneWidget);
    final image = tester.widget<Image>(find.byKey(const Key('ad.image')));
    expect(image.excludeFromSemantics, isTrue, reason: 'the title says it');
    expect((image.image as NetworkImage).url, sampleHouseAd.imageUrl);
    expect(find.text('Remove ads with Pro'), findsOneWidget);
  });

  testWidgets('a loaded image is a small thumbnail beside the title', (
    tester,
  ) async {
    // The prototype's compact row: a 52 dp square image on the left, the
    // title beside it, not a picture as wide as the screen.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugNetworkImageHttpClientProvider = imageHttpClient;
    // An address of its own, and a clean cache before and after: the other
    // tests' failed loads of the sample ad's image must not stand in for it,
    // nor this loaded one for theirs.
    imageCache
      ..clear()
      ..clearLiveImages();
    addTearDown(
      () => imageCache
        ..clear()
        ..clearLiveImages(),
    );

    await _pump(
      tester,
      FakeAdSource(
        ad: const HouseAd(
          id: 7,
          title: 'GymShark PH: 20% off',
          imageUrl: 'http://fitsync.test/storage/ads/loaded.png',
          linkUrl: 'https://shop.example.ph/promo',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final image = find.descendant(
      of: find.byKey(const Key('ad.image')),
      matching: find.byType(RawImage),
    );
    expect(tester.getSize(image), const Size(52, 52));
    final title = find.text('GymShark PH: 20% off');
    expect(
      tester.getTopLeft(title).dx,
      greaterThan(tester.getTopRight(image).dx),
      reason: 'the title sits beside the image, not under it',
    );
    expect(tester.getSize(find.byType(FsCard)).height, lessThan(100));
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('the view is reported exactly once across rebuilds', (
    tester,
  ) async {
    final source = FakeAdSource(ad: sampleHouseAd);
    await _pump(tester, source);
    // A theme change and a text size change rebuild the whole tree.
    await _pump(tester, source, dark: true);
    await _pump(tester, source, textScale: 1.5);

    expect(source.calls, ['viewed 7']);
    expect(source.currentCalls, 1);
  });

  // Home and Nutrition are lists: the card is disposed when it scrolls off
  // and built again when it comes back. That is the same ad, and not
  // another view.
  testWidgets('scrolling away and back keeps the ad and counts no new view', (
    tester,
  ) async {
    final source = FakeAdSource(ad: sampleHouseAd);
    await _pumpLong(tester, source, const [AdSlot(placement: 'home')]);
    expect(source.calls, ['viewed 7']);

    // Another ad is running by now: the slot must not swap to it.
    source.ad = _otherAd;
    await tester.drag(find.byType(ListView), const Offset(0, -2500));
    await tester.pumpAndSettle();
    expect(find.byType(FsCard), findsNothing, reason: 'the card was disposed');
    await tester.drag(find.byType(ListView), const Offset(0, 2500));
    await tester.pumpAndSettle();

    expect(find.text(sampleHouseAd.title), findsOneWidget);
    expect(find.text(_otherAd.title), findsNothing);
    expect(source.currentCalls, 1);
    expect(source.calls, ['viewed 7']);
  });

  testWidgets('the same ad counts one view in each placement', (tester) async {
    final source = FakeAdSource(ad: sampleHouseAd);
    await _pumpLong(tester, source, const [
      AdSlot(placement: 'home'),
      AdSlot(placement: 'nutrition'),
    ]);
    await tester.drag(find.byType(ListView), const Offset(0, -2500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 2500));
    await tester.pumpAndSettle();

    expect(source.calls, ['viewed 7', 'viewed 7']);
    expect(source.currentCalls, 1);
  });

  testWidgets('tapping a card with a link reports the tap, then opens it', (
    tester,
  ) async {
    final log = await _pump(tester, FakeAdSource(ad: sampleHouseAd));
    await tester.tap(find.byType(FsCard));
    await tester.pumpAndSettle();

    expect(log, ['viewed 7', 'tapped 7', 'open https://shop.example.ph/promo']);
  });

  testWidgets('a card whose image fails keeps its title and 48 dp', (
    tester,
  ) async {
    // The test HTTP client answers every request 400, so the image fails.
    await _pump(tester, FakeAdSource(ad: sampleHouseAd));

    final card = find.byType(FsCard);
    expect(
      find.byKey(const Key('ad.thumb')),
      findsNothing,
      reason: 'a failed image leaves no empty frame',
    );
    expect(find.text('GymShark PH: 20% off'), findsOneWidget);
    expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a screen reader hears the title, once, when the image fails', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // The test HTTP client answers every request 400, so the image fails.
    await _pump(tester, FakeAdSource(ad: sampleHouseAd));

    expect(
      find.bySemanticsLabel(RegExp('GymShark PH: 20% off')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp('GymShark PH: 20% off[\\s\\S]*GymShark PH: 20% off'),
      ),
      findsNothing,
      reason: 'the title is said once, not by both image and text',
    );
    handle.dispose();
  });

  testWidgets('a card without a link cannot be tapped', (tester) async {
    final log = await _pump(
      tester,
      FakeAdSource(
        ad: const HouseAd(
          id: 3,
          title: 'Local gym',
          imageUrl: 'http://fitsync.test/storage/ads/3.png',
        ),
      ),
    );
    expect(tester.widget<FsCard>(find.byType(FsCard)).onTap, isNull);
    await tester.tap(find.byType(FsCard));
    await tester.pumpAndSettle();

    expect(log, ['viewed 3']);
  });

  testWidgets('"Remove ads with Pro" is 48 dp tall and opens the Pro screen', (
    tester,
  ) async {
    await _pump(tester, FakeAdSource(ad: sampleHouseAd));
    final link = find.byKey(const Key('ad.removeWithPro'));
    expect(tester.getSize(link).height, greaterThanOrEqualTo(48));

    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(ProScreen), findsOneWidget);
  });

  testWidgets('a Pro member sees nothing, and no ad is asked for', (
    tester,
  ) async {
    final source = FakeAdSource(ad: sampleHouseAd);
    await _pump(tester, source, premium: true);

    expect(find.byType(FsCard), findsNothing);
    expect(find.text('Remove ads with Pro'), findsNothing);
    expect(source.currentCalls, 0);
    expect(source.calls, isEmpty);
  });

  testWidgets('no ad running: nothing is shown', (tester) async {
    final source = FakeAdSource();
    await _pump(tester, source);

    expect(source.currentCalls, 1);
    expect(find.byType(FsCard), findsNothing);
    expect(find.text('Remove ads with Pro'), findsNothing);
    expect(source.calls, isEmpty);
  });

  testWidgets('a failed fetch shows nothing, not even an error', (
    tester,
  ) async {
    final source = FakeAdSource(error: Exception('offline'));
    await _pump(tester, source);

    expect(find.byType(FsCard), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(find.byType(FsErrorLine), findsNothing);
    // Asked once: a failed ad is not worth asking again for.
    expect(source.currentCalls, 1);
  });

  testWidgets('2x text on a 360x640 phone fits, light and dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      await _pump(
        tester,
        FakeAdSource(ad: sampleHouseAd),
        dark: dark,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('GymShark PH: 20% off'), findsOneWidget);
      expect(find.text('Remove ads with Pro'), findsOneWidget);
    }
  });
}
