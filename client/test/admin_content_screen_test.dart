import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/admin/presentation/ad_form_screen.dart';
import 'package:fitsync/features/admin/presentation/ads_tab.dart';
import 'package:fitsync/features/admin/presentation/animations_tab.dart';
import 'package:fitsync/features/admin/presentation/content_screen.dart';
import 'package:fitsync/features/admin/presentation/meals_tab.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';

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
        home: const Scaffold(body: ContentScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

final _add = find.byKey(const Key('admin.content.add'));

Future<void> _segment(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(FsSegmented), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Animations, with no add button', (tester) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('Content'), findsOneWidget);
    for (final label in ['Animations', 'Meals', 'Ads']) {
      expect(
        find.descendant(
          of: find.byType(FsSegmented),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.byType(AnimationsTab), findsOneWidget);
    expect(_add, findsNothing);
  });

  testWidgets('Meals shows the foods and an Add food button', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        foods: (_, _, _) async => foodsPage([sampleFood(name: 'Turon')]),
      ),
    );

    await _segment(tester, 'Meals');

    expect(find.byType(MealsTab), findsOneWidget);
    expect(find.text('Turon'), findsOneWidget);
    expect(_add, findsOneWidget);
    expect(find.byTooltip('Add food'), findsOneWidget);
  });

  testWidgets('Ads shows the ads, and its + opens a new ad', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(ads: () async => [sampleAd(title: 'Gym promo')]),
    );

    await _segment(tester, 'Ads');

    expect(find.byType(AdsTab), findsOneWidget);
    expect(find.text('Gym promo'), findsOneWidget);
    expect(find.byTooltip('Add ad'), findsOneWidget);

    await tester.tap(_add);
    await tester.pumpAndSettle();
    expect(tester.widget<AdFormScreen>(find.byType(AdFormScreen)).ad, isNull);
    expect(find.text('New ad'), findsOneWidget);
  });

  testWidgets('a segment keeps its search when another is opened', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository());

    await tester.enterText(
      find.byKey(const Key('admin.exercises.search')),
      'squat',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await _segment(tester, 'Meals');
    await _segment(tester, 'Animations');

    expect(find.text('squat'), findsOneWidget);
    expect(find.byType(AnimationsTab), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(tester, FakeAdminRepository(), textScale: 2.0);
    for (final label in ['Meals', 'Ads', 'Animations']) {
      await _segment(tester, label);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(tester, FakeAdminRepository(), dark: true);

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Content'))).brightness,
      Brightness.dark,
    );
  });
}
