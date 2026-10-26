import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/pro/domain/pro_status.dart';
import 'package:fitsync/features/pro/presentation/pro_screen.dart';
import 'package:fitsync/features/pro/presentation/providers.dart';

import 'helpers/fake_pro_repository.dart';

class _Opener {
  final List<Uri> opened = [];
  bool answer = true;
  Object? error;
  Future<bool> call(Uri uri) async {
    opened.add(uri);
    if (error != null) throw error!;
    return answer;
  }
}

Future<(FakeProRepository, _Opener)> _pump(
  WidgetTester tester, {
  ProStatus status = freeStatus,
}) async {
  final repo = FakeProRepository(status);
  final opener = _Opener();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        proRepositoryProvider.overrideWithValue(repo),
        proCheckoutOpenerProvider.overrideWithValue(opener.call),
      ],
      child: MaterialApp(theme: fsLightTheme(), home: const ProScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, opener);
}

Finder _inside(String key, Finder f) =>
    find.descendant(of: find.byKey(Key(key)), matching: f);

void main() {
  testWidgets(
    'a free user picks a plan; annual is picked first and named for a screen reader',
    (tester) async {
      await _pump(tester);
      expect(find.text('Pay ₱1,788 with PayMongo'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('pro.plan.annual'))),
        isSemantics(
          label: 'Annual, ₱149 a month, billed ₱1,788 yearly',
          isSelected: true,
          isButton: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('pro.plan.monthly'))),
        isSemantics(label: 'Monthly, ₱249 a month', isSelected: false),
      );
      expect(_inside('pro.plan.annual', find.text('-40%')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pro.plan.monthly')));
      await tester.pump();
      expect(find.text('Pay ₱249 with PayMongo'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('pro.plan.monthly'))),
        isSemantics(isSelected: true),
      );
    },
  );

  testWidgets(
    'what Pro unlocks is what Pro gates, and nothing is sold as "planned"',
    (tester) async {
      await _pump(tester);
      expect(
        _inside('pro.today', find.textContaining('muscle')),
        findsNWidgets(2),
      );
      expect(
        _inside('pro.today', find.textContaining('Food photo')),
        findsOneWidget,
      );
      expect(
        _inside(
          'pro.today',
          find.text('Unlimited AI coaching cues (free: 3 exercises a day)'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pro.planned')), findsNothing);
      expect(find.textContaining('meal planning'), findsNothing);
      expect(find.textContaining('no way to buy'), findsNothing);
      expect(
        find.textContaining('test mode', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Test mode', findRichText: true),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Pay opens PayMongo, then the screen waits and checks by itself until it is paid',
    (tester) async {
      final (repo, opener) = await _pump(tester);
      repo.confirmAnswers
        ..add(
          ProConfirmation(state: ProPaymentState.pending, status: freeStatus),
        )
        ..add(
          ProConfirmation(
            state: ProPaymentState.paid,
            status: paidStatus(until: DateTime(2026, 11, 26, 12)),
          ),
        );
      repo.statusValue = paidStatus(until: DateTime(2026, 11, 26, 12));

      await tester.tap(find.byKey(const Key('pro.pay')));
      await tester.pump();
      expect(repo.checkouts, [ProPlan.annual]);
      expect(opener.opened, [Uri.parse('https://checkout.example/cs_7')]);
      expect(find.byKey(const Key('pro.waiting')), findsOneWidget);
      expect(find.byKey(const Key('pro.pay')), findsNothing);

      await tester.pump(proPollEvery);
      await tester.pump();
      expect(repo.confirms, [7]);
      expect(
        find.byKey(const Key('pro.waiting')),
        findsOneWidget,
        reason: 'a pending answer while polling keeps waiting',
      );

      await tester.pump(proPollEvery);
      await tester.pumpAndSettle();
      expect(repo.confirms, [7, 7]);
      expect(find.text("You're Pro until 26 Nov 2026"), findsOneWidget);
      expect(find.byKey(const Key('pro.waiting')), findsNothing);
      expect(find.byKey(const Key('pro.status')), findsOneWidget);

      await tester.pump(proPollEvery * 3);
      expect(repo.confirms, [7, 7], reason: 'polling stops once paid');
    },
  );

  testWidgets(
    'asking by hand: "not completed", then open the page again or choose another plan',
    (tester) async {
      final (repo, opener) = await _pump(tester);
      await tester.tap(find.byKey(const Key('pro.pay')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pro.check')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('pro.notCompleted')), findsOneWidget);
      expect(find.text('Payment not completed'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pro.reopen')));
      await tester.pump();
      expect(opener.opened.length, 2);
      expect(find.byKey(const Key('pro.waiting')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pro.otherPlan')));
      await tester.pump();
      expect(find.byKey(const Key('pro.pay')), findsOneWidget);
      final checks = repo.confirms.length;
      await tester.pump(proPollEvery * 2);
      expect(
        repo.confirms.length,
        checks,
        reason: 'no polling after choosing another plan',
      );
    },
  );

  testWidgets('a failed check says the money is safe and offers Try again', (
    tester,
  ) async {
    final (repo, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('pro.pay')));
    await tester.pump();
    repo.confirmError = const ApiException('NETWORK_ERROR', 'offline');
    await tester.tap(find.byKey(const Key('pro.check')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('pro.checkFailed')), findsOneWidget);
    expect(
      find.text("Couldn't check your payment. Your money is safe — try again."),
      findsOneWidget,
    );

    repo.confirmError = null;
    repo.confirmAnswers.add(
      ProConfirmation(state: ProPaymentState.paid, status: paidStatus()),
    );
    repo.statusValue = paidStatus();
    await tester.tap(find.byKey(const Key('pro.retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pro.paid')), findsOneWidget);
  });

  testWidgets(
    'a checkout that fails, or a page that will not open, keeps the plans and says so',
    (tester) async {
      final (repo, opener) = await _pump(tester);
      repo.checkoutError = const ApiException(
        'PAYMENTS_UNAVAILABLE',
        "Couldn't open the payment page. Try again.",
      );
      await tester.tap(find.byKey(const Key('pro.pay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro.openError')), findsOneWidget);
      expect(find.byKey(const Key('pro.pay')), findsOneWidget);
      expect(opener.opened, isEmpty);

      repo.checkoutError = null;
      opener.answer = false;
      await tester.tap(find.byKey(const Key('pro.pay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro.openError')), findsOneWidget);
      expect(find.byKey(const Key('pro.waiting')), findsNothing);
    },
  );

  testWidgets(
    'a page opener that throws (as Android does) frees the Pay button and says so',
    (tester) async {
      final (_, opener) = await _pump(tester);
      opener.error = PlatformException(code: 'ACTIVITY_NOT_FOUND');
      await tester.tap(find.byKey(const Key('pro.pay')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('pro.openError')), findsOneWidget);
      expect(find.byKey(const Key('pro.waiting')), findsNothing);
      final pay = tester.widget<FsButton>(find.byKey(const Key('pro.pay')));
      expect(pay.busy, isFalse);
      expect(pay.onPressed, isNotNull);
    },
  );

  testWidgets(
    'a payment finished after the screen closed is confirmed when it opens again',
    (tester) async {
      final repo = FakeProRepository();
      final opener = _Opener();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            proRepositoryProvider.overrideWithValue(repo),
            proCheckoutOpenerProvider.overrideWithValue(opener.call),
          ],
          child: MaterialApp(
            theme: fsLightTheme(),
            home: Builder(
              builder: (context) => TextButton(
                key: const Key('home.openPro'),
                onPressed: () => openProScreen(context),
                child: const Text('Pro'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('home.openPro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pro.pay')));
      await tester.pump();
      expect(find.byKey(const Key('pro.waiting')), findsOneWidget);

      // The user pays on PayMongo's page, then leaves the screen before the
      // next check.
      await tester.tap(find.byKey(const Key('pro.close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pro.pay')), findsNothing);
      expect(repo.confirms, isEmpty);

      repo.confirmAnswers.add(
        ProConfirmation(
          state: ProPaymentState.paid,
          status: paidStatus(until: DateTime(2026, 11, 26, 12)),
        ),
      );
      repo.statusValue = paidStatus(until: DateTime(2026, 11, 26, 12));
      await tester.tap(find.byKey(const Key('home.openPro')));
      await tester.pumpAndSettle();
      expect(repo.confirms, [7]);
      expect(find.text("You're Pro until 26 Nov 2026"), findsOneWidget);

      // Confirmed once: opening the screen again asks nothing more.
      await tester.tap(find.byKey(const Key('pro.close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.openPro')));
      await tester.pumpAndSettle();
      expect(repo.confirms, [7]);
    },
  );

  testWidgets(
    'an unpaid attempt left behind is checked quietly and leaves the plans as they were',
    (tester) async {
      final repo = FakeProRepository();
      final opener = _Opener();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            proRepositoryProvider.overrideWithValue(repo),
            proCheckoutOpenerProvider.overrideWithValue(opener.call),
          ],
          child: MaterialApp(
            theme: fsLightTheme(),
            home: Builder(
              builder: (context) => TextButton(
                key: const Key('home.openPro'),
                onPressed: () => openProScreen(context),
                child: const Text('Pro'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('home.openPro')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pro.pay')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pro.close')));
      await tester.pumpAndSettle();

      repo.confirmError = const ApiException('NETWORK_ERROR', 'offline');
      await tester.tap(find.byKey(const Key('home.openPro')));
      await tester.pumpAndSettle();
      expect(repo.confirms, [7]);
      expect(find.byKey(const Key('pro.checkFailed')), findsNothing);
      expect(find.byKey(const Key('pro.pay')), findsOneWidget);

      await tester.pump(proPollEvery * 2);
      expect(repo.confirms, [
        7,
      ], reason: 'no polling for an attempt left behind');
    },
  );

  testWidgets('Pay locks while the checkout is being made', (tester) async {
    final (repo, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('pro.pay')));
    await tester.tap(find.byKey(const Key('pro.pay')), warnIfMissed: false);
    await tester.pump();
    expect(repo.checkouts.length, 1);
  });

  testWidgets('paid: the end date and how it was paid, with plans to extend', (
    tester,
  ) async {
    await _pump(
      tester,
      status: paidStatus(until: DateTime(2026, 11, 26, 12), method: 'gcash'),
    );
    expect(
      _inside(
        'pro.status',
        find.text('FitSync Pro · until 26 Nov 2026 · paid with GCash'),
      ),
      findsOneWidget,
    );
    expect(find.text('EXTEND YOUR PRO'), findsOneWidget);
    expect(find.byKey(const Key('pro.pay')), findsOneWidget);
    expect(find.byKey(const Key('pro.endsSoon')), findsNothing);
  });

  testWidgets('ending within 3 days: a reminder to renew', (tester) async {
    await _pump(
      tester,
      status: paidStatus(until: DateTime(2026, 11, 26, 12), endsSoon: true),
    );
    expect(
      find.text(
        'Pro ends on 26 Nov. Renew to keep Snap a meal and your analytics.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('granted by hand: Pro with no end and nothing to buy', (
    tester,
  ) async {
    await _pump(tester, status: grantedStatus);
    expect(
      _inside('pro.status', find.text('FitSync Pro (granted)')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pro.pay')), findsNothing);
    expect(find.byKey(const Key('pro.plan.annual')), findsNothing);
    expect(find.byKey(const Key('pro.today')), findsOneWidget);
  });

  testWidgets('a status that will not load offers Try again', (tester) async {
    final repo = FakeProRepository()
      ..statusError = const ApiException('NETWORK_ERROR', 'offline');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [proRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: fsLightTheme(), home: const ProScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pro.retryStatus')), findsOneWidget);
    repo.statusError = null;
    await tester.tap(find.byKey(const Key('pro.retryStatus')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pro.pay')), findsOneWidget);
  });

  testWidgets('coming back to the app checks at once', (tester) async {
    final (repo, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('pro.pay')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(repo.confirms, [7]);
    expect(find.byKey(const Key('pro.notCompleted')), findsOneWidget);
  });

  testWidgets('the close button leaves', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('pro.close')), findsOneWidget);
  });
}
