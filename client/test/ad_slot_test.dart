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
    expect(image.semanticLabel, 'GymShark PH: 20% off');
    expect((image.image as NetworkImage).url, sampleHouseAd.imageUrl);
    expect(find.text('Remove ads with Pro'), findsOneWidget);
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
      find.descendant(of: card, matching: find.byType(AspectRatio)),
      findsNothing,
      reason: 'a failed image leaves no empty frame',
    );
    expect(find.text('GymShark PH: 20% off'), findsOneWidget);
    expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
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
