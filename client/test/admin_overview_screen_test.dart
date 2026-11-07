import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/domain/admin_user.dart';
import 'package:fitsync/features/admin/presentation/overview_screen.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';

import 'helpers/fake_admin_repository.dart';

/// Signed in as an admin; counts sign-outs instead of clearing anything.
class _AdminAuth extends AuthController {
  int signOuts = 0;

  @override
  Future<AuthState> build() async => const AuthState(
    AuthStatus.admin,
    null,
    null,
    AdminUser(id: 1, email: 'admin@fitsync.ph', fullName: 'Ana Reyes'),
  );

  @override
  Future<void> signOut() async => signOuts++;
}

Future<(ProviderContainer, _AdminAuth)> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  bool dark = false,
  double textScale = 1.0,
  bool settle = true,
}) async {
  final auth = _AdminAuth();
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(() => auth),
    ],
  );
  addTearDown(container.dispose);
  // The tab provider is autoDispose and the screen only writes it; held
  // here so the test can read what was selected.
  container.listen(adminTabProvider, (_, _) {});
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
        home: const Scaffold(body: OverviewScreen()),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (container, auth);
}

void main() {
  testWidgets('header names the screen and Sign out signs the admin out', (
    tester,
  ) async {
    final (_, auth) = await _pump(tester, FakeAdminRepository());

    expect(find.text('FitSync Admin'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    final signOut = find.byKey(const Key('admin.signOut'));
    expect(
      find.descendant(of: signOut, matching: find.text('Sign out')),
      findsOneWidget,
    );
    expect(tester.getSize(signOut).height, greaterThanOrEqualTo(48));

    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
  });

  testWidgets('shows the four cards with their figures and changes', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('Active users'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('Pro members'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Pro revenue'), findsOneWidget);
    expect(find.text('₱498'), findsOneWidget);
    expect(find.text('+₱249'), findsOneWidget);
    expect(find.text('Ad revenue'), findsOneWidget);
    expect(find.text('₱0'), findsOneWidget);
    expect(find.text('No change'), findsOneWidget);
    expect(find.text('this month'), findsNWidgets(2));

    // Up twice (Active users, Pro revenue), never down; no arrow on
    // No change, none on Pro members.
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
  });

  testWidgets('each card reads its value and its change aloud', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, FakeAdminRepository());

    expect(
      find.bySemanticsLabel('Active users, 14, up 3 from the 30 days before'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Pro members, 3'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Pro revenue this month, ₱498, up ₱249 from last month',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Ad revenue this month, ₱0, no change from last month',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a fall shows a minus, a down arrow and the error red', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeAdminRepository(
        overview: () async => sampleOverview(
          activeUsers: 9,
          previousActiveUsers: 11,
          proThisMonth: 249,
          proLastMonth: 498,
        ),
      ),
    );

    expect(find.text('−2'), findsOneWidget);
    expect(find.text('−₱249'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(2));
    final context = tester.element(find.text('−2'));
    expect(tester.widget<Text>(find.text('−2')).style?.color, context.fs.red);
  });

  testWidgets('a rise is drawn in the accent text colour', (tester) async {
    await _pump(tester, FakeAdminRepository());

    final context = tester.element(find.text('+3'));
    expect(
      tester.widget<Text>(find.text('+3')).style?.color,
      context.fs.accentText,
    );
    expect(
      tester.widget<Text>(find.text('No change')).style?.color,
      context.fs.text3,
    );
  });

  testWidgets('New sign-ups shows the total and a bar per day', (tester) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('New sign-ups'), findsOneWidget);
    expect(find.text('12 new trainees'), findsOneWidget);
    final chart = tester.widget<FsBarChart>(find.byType(FsBarChart));
    expect(chart.label, 'New sign-ups, last 30 days: 12');
    expect(chart.bars, hasLength(30));
    expect(chart.bars.first.tooltip, 'Oct 9: 0');
    expect(chart.bars[27].tooltip, 'Nov 5: 2');
    expect(chart.bars[27].value, 2);
  });

  testWidgets('one sign-up reads in the singular', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(
        overview: () async {
          final base = sampleOverview();
          return AdminOverview(
            today: base.today,
            activeUsers: base.activeUsers,
            previousActiveUsers: base.previousActiveUsers,
            proMembers: base.proMembers,
            proRevenueThisMonth: base.proRevenueThisMonth,
            proRevenueLastMonth: base.proRevenueLastMonth,
            adRevenueThisMonth: base.adRevenueThisMonth,
            adRevenueLastMonth: base.adRevenueLastMonth,
            signupsTotal: 1,
            signupDays: base.signupDays,
          );
        },
      ),
    );

    expect(find.text('1 new trainee'), findsOneWidget);
  });

  testWidgets('cards open the Users and Revenue tabs', (tester) async {
    final (container, _) = await _pump(tester, FakeAdminRepository());

    await tester.tap(find.text('Active users'));
    await tester.pump();
    expect(container.read(adminTabProvider), (index: 1, usersFilter: 'all'));

    await tester.tap(find.text('Pro members'));
    await tester.pump();
    expect(container.read(adminTabProvider), (index: 1, usersFilter: 'pro'));

    await tester.tap(find.text('Pro revenue'));
    await tester.pump();
    expect(container.read(adminTabProvider).index, 3);

    container.read(adminTabProvider.notifier).select(0);
    await tester.tap(find.text('Ad revenue'));
    await tester.pump();
    expect(container.read(adminTabProvider).index, 3);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final pending = Completer<AdminOverview>();
    await _pump(
      tester,
      FakeAdminRepository(overview: () => pending.future),
      settle: false,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Sign out stays reachable while the figures load.
    expect(find.byKey(const Key('admin.signOut')), findsOneWidget);
    pending.complete(sampleOverview());
    await tester.pumpAndSettle();
  });

  testWidgets('a failed load offers Try again, which fetches again', (
    tester,
  ) async {
    var fail = true;
    final repo = FakeAdminRepository(
      overview: () async {
        if (fail) throw refused;
        return sampleOverview();
      },
    );
    await _pump(tester, repo);

    expect(find.text('The server said no.'), findsOneWidget);
    expect(find.byKey(const Key('admin.signOut')), findsOneWidget);
    expect(repo.overviewCalls, 1);

    fail = false;
    await tester.tap(find.byKey(const Key('admin.overview.retry')));
    await tester.pumpAndSettle();

    expect(repo.overviewCalls, 2);
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('pulling down fetches the figures again', (tester) async {
    var active = 14;
    final repo = FakeAdminRepository(
      overview: () async => sampleOverview(activeUsers: active),
    );
    await _pump(tester, repo);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    active = 20;
    await tester.fling(find.text('Active users'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(repo.overviewCalls, 2);
    expect(find.text('20'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(tester, FakeAdminRepository(), textScale: 2.0);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(tester, FakeAdminRepository(), dark: true);

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Overview'))).brightness,
      Brightness.dark,
    );
  });
}
