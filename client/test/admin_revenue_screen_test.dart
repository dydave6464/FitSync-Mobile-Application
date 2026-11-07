import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/revenue_chart.dart';
import 'package:fitsync/features/admin/presentation/revenue_screen.dart';

import 'helpers/fake_admin_repository.dart';

/// Today is 7 November 2026 in Manila, so November is the current month.
Future<void> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  bool dark = false,
  double textScale = 1.0,
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      adminTodayProvider.overrideWithValue('2026-11-07'),
    ],
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
        home: const Scaffold(body: RevenueScreen()),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// The repository answering [sampleRevenue] for any month, each with its
/// own month and [firstMonth].
FakeAdminRepository _repo({String? firstMonth = '2026-10'}) =>
    FakeAdminRepository(
      onRevenue: (month) async =>
          sampleRevenue(month: month ?? '2026-11', firstMonth: firstMonth),
    );

Finder _prev() => find.ancestor(
  of: find.byTooltip('Previous month'),
  matching: find.byType(IconButton),
);
Finder _next() => find.ancestor(
  of: find.byTooltip('Next month'),
  matching: find.byType(IconButton),
);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<IconButton>(button).onPressed != null;

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the month, its total and its change from the month '
      'before', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    expect(repo.revenueCalls, [null]);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('₱3,486'), findsWidgets);
    expect(find.text('this month'), findsOneWidget);
    expect(find.text('+₱747'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('splits the month into Pro subscriptions and ads', (
    tester,
  ) async {
    await _pump(tester, _repo());

    expect(find.text('Pro subscriptions'), findsOneWidget);
    expect(find.text('₱2,286'), findsOneWidget);
    expect(find.text('2 monthly · 1 yearly'), findsOneWidget);
    expect(find.text('Ads'), findsWidgets);
    expect(find.text('₱1,200'), findsWidgets);
    expect(find.text('1 ad'), findsOneWidget);
  });

  testWidgets('says "2 ads" for more than one ad', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(onRevenue: (_) async => sampleRevenue(adsCount: 2)),
    );

    expect(find.text('2 ads'), findsOneWidget);
  });

  testWidgets('draws the last six months', (tester) async {
    await _pump(tester, _repo());
    await _scrollTo(tester, find.byType(RevenueChart));

    expect(find.text('Last 6 months'), findsOneWidget);
    final chart = tester.widget<RevenueChart>(find.byType(RevenueChart));
    expect(chart.months, sampleRevenueBars);
  });

  group('month switcher', () {
    testWidgets('both buttons are 48 dp and named; next is off on the '
        'current month', (tester) async {
      await _pump(tester, _repo());

      for (final button in [_prev(), _next()]) {
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(_enabled(tester, _prev()), isTrue);
      expect(_enabled(tester, _next()), isFalse);
    });

    testWidgets('previous asks for the month before and next comes back', (
      tester,
    ) async {
      final repo = _repo(firstMonth: '2026-01');
      await _pump(tester, repo);

      await tester.tap(_prev());
      await tester.pumpAndSettle();

      expect(repo.revenueCalls.last, '2026-10');
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('this month'), findsNothing);
      expect(_enabled(tester, _next()), isTrue);

      await tester.tap(_prev());
      await tester.pumpAndSettle();
      expect(repo.revenueCalls.last, '2026-09');

      await tester.tap(_next());
      await tester.pumpAndSettle();
      await tester.tap(_next());
      await tester.pumpAndSettle();

      // Back on the current month, the server's own "this month" again.
      expect(repo.revenueCalls.last, isNull);
      expect(find.text('November 2026'), findsOneWidget);
      expect(_enabled(tester, _next()), isFalse);
    });

    testWidgets('previous stops at the month of the first payment', (
      tester,
    ) async {
      await _pump(tester, _repo(firstMonth: '2026-10'));

      await tester.tap(_prev());
      await tester.pumpAndSettle();

      expect(find.text('October 2026'), findsOneWidget);
      expect(_enabled(tester, _prev()), isFalse);
    });

    testWidgets("the server's month wins over the phone's at a month's edge", (
      tester,
    ) async {
      // The phone still says 31 October; the server is already in November.
      final repo = _repo();
      final container = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(repo),
          adminTodayProvider.overrideWithValue('2026-10-31'),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fsLightTheme(),
            home: const Scaffold(body: RevenueScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('November 2026'), findsOneWidget);
      expect(_enabled(tester, _next()), isFalse);
      await tester.tap(_prev());
      await tester.pumpAndSettle();

      expect(repo.revenueCalls.last, '2026-10');
      expect(find.text('October 2026'), findsOneWidget);
    });

    testWidgets('previous is off when nothing was ever paid', (tester) async {
      await _pump(tester, _repo(firstMonth: null));

      expect(_enabled(tester, _prev()), isFalse);
    });

    testWidgets('previous stops 24 months back', (tester) async {
      final repo = _repo(firstMonth: '2020-01');
      await _pump(tester, repo);

      for (var i = 0; i < 24; i++) {
        await tester.tap(_prev());
        await tester.pumpAndSettle();
      }

      expect(repo.revenueCalls.last, '2024-11');
      expect(find.text('November 2024'), findsOneWidget);
      expect(_enabled(tester, _prev()), isFalse);
    });
  });

  testWidgets('lists the Pro payments with plan, method, amount and day', (
    tester,
  ) async {
    await _pump(tester, _repo());
    await _scrollTo(tester, find.text('Maria Santos'));

    expect(find.text('Pro payments'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    // A no-break space keeps each day whole.
    expect(find.text('Monthly · GCash · 5\u00A0Nov'), findsOneWidget);
    expect(find.text('Monthly · Maya · 3\u00A0Nov'), findsOneWidget);
    expect(find.text('Yearly · — · 1\u00A0Nov'), findsOneWidget);
    expect(find.text('₱249'), findsNWidgets(2));
    expect(find.text('₱1,788'), findsOneWidget);
  });

  testWidgets('a deleted account is named as one, in the dim ink', (
    tester,
  ) async {
    await _pump(tester, _repo());
    await _scrollTo(tester, find.text('Deleted account'));

    final text = tester.widget<Text>(find.text('Deleted account'));
    expect(text.style?.color, FsTokens.light.text3);
  });

  testWidgets('the card method reads as Card', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        onRevenue: (_) async => sampleRevenue(
          proPayments: const [
            RevenueProPayment(
              paymentId: 9,
              name: 'Ana Cruz',
              plan: 'annual',
              method: 'card',
              amountPhp: 1788,
              paidOn: '2026-11-02',
            ),
          ],
        ),
      ),
    );
    await _scrollTo(tester, find.text('Ana Cruz'));

    expect(find.text('Yearly · Card · 2\u00A0Nov'), findsOneWidget);
  });

  testWidgets('lists the ad payments with advertiser, title and run', (
    tester,
  ) async {
    await _pump(tester, _repo());
    await _scrollTo(tester, find.text('GymShark PH'));

    expect(find.text('Ad payments'), findsOneWidget);
    expect(find.text('GymShark PH'), findsOneWidget);
    expect(find.text('Protein bars, 20% off · 1–30 Nov'), findsOneWidget);
  });

  testWidgets('a month with no payments says so', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        onRevenue: (_) async => sampleRevenue(
          totalPhp: 0,
          proTotalPhp: 0,
          adsTotalPhp: 0,
          proMonthly: 0,
          proAnnual: 0,
          adsCount: 0,
          proPayments: const [],
          adPayments: const [],
        ),
      ),
    );
    await _scrollTo(tester, find.text('No payments in November 2026.'));

    expect(find.text('Pro payments'), findsNothing);
    expect(find.text('Ad payments'), findsNothing);
  });

  testWidgets('shows a spinner while the month loads', (tester) async {
    final pending = Completer<RevenueMonth>();
    await _pump(
      tester,
      FakeAdminRepository(onRevenue: (_) => pending.future),
      settle: false,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    pending.complete(sampleRevenue());
    await tester.pumpAndSettle();
  });

  testWidgets('a failure offers a retry that asks again', (tester) async {
    var fail = true;
    final repo = FakeAdminRepository(
      onRevenue: (_) async => fail ? throw refused : sampleRevenue(),
    );
    await _pump(tester, repo);

    expect(find.text('The server said no.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('admin.revenue.retry')));
    await tester.pumpAndSettle();

    expect(find.text('Pro subscriptions'), findsOneWidget);
  });

  testWidgets('pulling down asks for the month again', (tester) async {
    final repo = _repo();
    await _pump(tester, repo);

    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repo.revenueCalls, [null, null]);
  });

  testWidgets('at 2x text the card titles and days do not break apart', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);
    await _pump(tester, _repo(), textScale: 2.0);

    // "Pro subscri" / "ptions" in a half-width card.
    final title = tester.renderObject<RenderParagraph>(
      find.text('Pro subscriptions'),
    );
    expect(title.size.height, lessThan(12 * 2 * 1.9));
    // "3" at the end of one line and "Nov" on the next.
    await _scrollTo(tester, find.textContaining('Maya'));
    final detail = tester.widget<Text>(find.textContaining('Maya'));
    expect(detail.data, contains('3\u00A0Nov'));
  });

  for (final dark in [false, true]) {
    testWidgets('fits a 360x640 phone at 2x text '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
      addTearDown(tester.view.reset);

      await _pump(tester, _repo(), dark: dark, textScale: 2.0);
      await _scrollTo(tester, find.text('GymShark PH'));

      expect(tester.takeException(), isNull);
    });
  }
}
