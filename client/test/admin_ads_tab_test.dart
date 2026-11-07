import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/presentation/ad_form_screen.dart';
import 'package:fitsync/features/admin/presentation/ads_tab.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/widgets/admin_widgets.dart';

import 'helpers/fake_admin_repository.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  bool dark = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [adminRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: AdsTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

StatusTag _tag(WidgetTester tester, String word) => tester.widget<StatusTag>(
  find.ancestor(of: find.text(word), matching: find.byType(StatusTag)),
);

void main() {
  testWidgets('a row shows the image, title, advertiser, run and counts', (
    tester,
  ) async {
    final repo = FakeAdminRepository(ads: () async => [sampleAd()]);
    await _pump(tester, repo);

    expect(repo.adsCalls, 1);
    expect(find.text('Protein bars, 20% off'), findsOneWidget);
    expect(find.text('GymShark PH · 1–30 Nov'), findsOneWidget);
    expect(find.text('1,204 views · 37 taps'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    final thumb = tester.widget<Image>(
      find.byKey(const ValueKey('admin.ad.5.image')),
    );
    expect(
      (thumb.image as NetworkImage).url,
      'http://fitsync.test/storage/ads/5.jpg',
    );
  });

  testWidgets('a run across two months names both', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        ads: () async => [
          sampleAd(startsOn: '2026-10-28', endsOn: '2026-11-03'),
        ],
      ),
    );

    expect(find.text('GymShark PH · 28 Oct – 3 Nov'), findsOneWidget);
  });

  testWidgets('each status says its word, coloured as the design has it', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeAdminRepository(
        ads: () async => [
          sampleAd(id: 1, status: 'running'),
          sampleAd(id: 2, status: 'scheduled'),
          sampleAd(id: 3, status: 'ended'),
          sampleAd(id: 4, status: 'paused', active: false),
        ],
      ),
    );
    final t = FsTokens.light;

    expect(_tag(tester, 'Running').color, t.accentText);
    // Blue and amber are too faint as words on the light tag, so they are
    // dots beside the word (the Pending tag's rule).
    expect(_tag(tester, 'Scheduled').dot, t.blue);
    expect(_tag(tester, 'Ended').color, t.text3);
    expect(_tag(tester, 'Paused').dot, t.amber);
  });

  testWidgets('a row reads as one sentence to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, FakeAdminRepository(ads: () async => [sampleAd()]));

    expect(
      find.bySemanticsLabel(
        'Protein bars, 20% off, GymShark PH · 1–30 Nov, '
        '1,204 views · 37 taps, Running',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('tapping a row opens it to edit', (tester) async {
    await _pump(tester, FakeAdminRepository(ads: () async => [sampleAd()]));

    await tester.tap(find.text('Protein bars, 20% off'));
    await tester.pumpAndSettle();

    final form = tester.widget<AdFormScreen>(find.byType(AdFormScreen));
    expect(form.ad?.id, 5);
    expect(find.text('Edit ad'), findsOneWidget);
  });

  testWidgets('no ads: says so, with a New ad button to the form', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('No ads yet.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.ads.new')));
    await tester.pumpAndSettle();

    expect(tester.widget<AdFormScreen>(find.byType(AdFormScreen)).ad, isNull);
    expect(find.text('New ad'), findsOneWidget);
  });

  testWidgets('a failed load offers Try again', (tester) async {
    var fail = true;
    final repo = FakeAdminRepository(
      ads: () async {
        if (fail) throw refused;
        return [sampleAd()];
      },
    );
    await _pump(tester, repo);

    expect(find.text('The server said no.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('admin.ads.retry')));
    await tester.pumpAndSettle();

    expect(find.text('Protein bars, 20% off'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      FakeAdminRepository(
        ads: () async => [
          sampleAd(
            id: 1,
            title: 'Protein bars and shakers, 20% off this whole month',
            advertiser: 'GymShark Philippines Incorporated',
            startsOn: '2026-12-28',
            endsOn: '2027-01-03',
            status: 'scheduled',
            views: 1204000,
            taps: 37000,
          ),
          sampleAd(id: 2, status: 'paused', active: false),
        ],
      ),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(ads: () async => [sampleAd()]),
      dark: true,
    );

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Protein bars, 20% off'))).brightness,
      Brightness.dark,
    );
  });
}
