import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/user_detail_screen.dart';
import 'package:fitsync/features/admin/presentation/users_screen.dart';
import 'package:fitsync/features/admin/presentation/widgets/admin_widgets.dart';

import 'helpers/fake_admin_repository.dart';

Future<ProviderContainer> _pump(
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
        home: const Scaffold(body: UsersScreen()),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return container;
}

/// [count] trainees, newest first, ids counting down from [count].
List<AdminUserRow> _rows(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    sampleRow(id: 1000 - i, fullName: 'Trainee $i'),
];

/// A server of [total] trainees in pages of 30.
FakeAdminRepository _paged(int total) => FakeAdminRepository(
  users: (q, filter, page) async {
    final start = (page - 1) * 30;
    final count = (total - start).clamp(0, 30);
    return usersPage(
      _rows(count, from: start),
      page: page,
      total: total,
    );
  },
);

void main() {
  testWidgets('shows the title, search, chips and the count line', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeAdminRepository(
        users: (_, _, _) async => usersPage(_rows(2), total: 28),
      ),
    );

    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Search name or email'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    for (final chip in ['All', 'Pro', 'Suspended']) {
      expect(find.text(chip), findsOneWidget);
    }
    expect(find.text('28 trainees'), findsOneWidget);
  });

  testWidgets('one trainee reads in the singular', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(users: (_, _, _) async => usersPage(_rows(1))),
    );

    expect(find.text('1 trainee'), findsOneWidget);
  });

  testWidgets('a row shows the trainee, their tags and last activity', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      FakeAdminRepository(
        users: (_, _, _) async => usersPage([
          sampleRow(
            id: 7,
            fullName: 'Juan Dela Cruz',
            email: 'juan@example.com',
            isPro: true,
            suspended: true,
            lastActiveOn: '2026-11-04',
          ),
          sampleRow(
            id: 6,
            fullName: 'Maria Santos',
            email: 'maria@example.com',
            lastActiveOn: null,
          ),
        ]),
      ),
    );

    expect(find.byType(InitialsAvatar), findsNWidgets(2));
    expect(find.text('JC'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('juan@example.com'), findsOneWidget);
    expect(
      find.widgetWithText(StatusTag, 'Pro'),
      findsOneWidget,
      reason: 'the Pro chip is a FsChip, the tag a StatusTag',
    );
    final suspended = find.widgetWithText(StatusTag, 'Suspended');
    expect(suspended, findsOneWidget);
    expect(
      tester.widget<StatusTag>(suspended).color,
      tester.element(suspended).fs.red,
    );
    expect(find.text('active 3 d ago'), findsOneWidget);
    expect(find.text('not active yet'), findsOneWidget);

    expect(
      find.bySemanticsLabel(
        'Juan Dela Cruz, juan@example.com, Pro, Suspended, active 3 d ago',
      ),
      findsOneWidget,
    );
    final row = find.byKey(const ValueKey('admin.user.7'));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    handle.dispose();
  });

  testWidgets("tapping a row opens that trainee's page", (tester) async {
    final repo = FakeAdminRepository(
      users: (_, _, _) async => usersPage([sampleRow(id: 7)]),
    );
    await _pump(tester, repo);

    await tester.tap(find.byKey(const ValueKey('admin.user.7')));
    await tester.pumpAndSettle();

    expect(find.byType(UserDetailScreen), findsOneWidget);
    expect(repo.userCalls, [7]);
  });

  testWidgets('typing searches once, 300 ms after the last key', (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      users: (_, _, _) async => usersPage(_rows(3)),
    );
    await _pump(tester, repo);
    expect(repo.usersCalls, hasLength(1));

    final field = find.byKey(const Key('admin.users.search'));
    for (final text in ['j', 'ju', 'jua']) {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repo.usersCalls, hasLength(1), reason: 'still typing');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repo.usersCalls, hasLength(2));
    expect(repo.usersCalls.last, (q: 'jua', filter: 'all', page: 1));
  });

  testWidgets('the chips pick one filter at a time', (tester) async {
    final repo = FakeAdminRepository(
      users: (_, _, _) async => usersPage(_rows(3)),
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Suspended'));
    await tester.pumpAndSettle();
    expect(repo.usersCalls.last, (q: '', filter: 'suspended', page: 1));

    await tester.tap(find.text('Pro'));
    await tester.pumpAndSettle();
    expect(repo.usersCalls.last, (q: '', filter: 'pro', page: 1));

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(repo.usersCalls.last, (q: '', filter: 'all', page: 1));
  });

  testWidgets("Overview's Pro members card selects the Pro chip", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repo = FakeAdminRepository(
      users: (_, _, _) async => usersPage(_rows(3)),
    );
    final container = await _pump(tester, repo);

    container.read(adminTabProvider.notifier).select(1, usersFilter: 'pro');
    await tester.pumpAndSettle();

    expect(repo.usersCalls.last.filter, 'pro');
    expect(
      tester.getSemantics(find.byKey(const Key('admin.users.filter.pro'))),
      isSemantics(isChecked: true, isInMutuallyExclusiveGroup: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('admin.users.filter.all'))),
      isSemantics(isChecked: false, isInMutuallyExclusiveGroup: true),
    );
    handle.dispose();
  });

  // The list is kept while the admin is on another tab: Overview's card
  // must not lead to a count older than the figure just tapped.
  testWidgets("Overview's card fetches the list again on the same chip", (
    tester,
  ) async {
    var total = 28;
    final repo = FakeAdminRepository(
      users: (_, _, _) async => usersPage(_rows(2), total: total),
    );
    final container = await _pump(tester, repo);
    expect(find.text('28 trainees'), findsOneWidget);

    total = 29;
    container.read(adminTabProvider.notifier).select(0);
    container.read(adminTabProvider.notifier).select(1, usersFilter: 'all');
    await tester.pumpAndSettle();

    expect(repo.usersCalls, hasLength(2));
    expect(repo.usersCalls.last, (q: '', filter: 'all', page: 1));
    expect(find.text('29 trainees'), findsOneWidget);
  });

  testWidgets('a tap on the bar keeps the list as it is', (tester) async {
    final repo = FakeAdminRepository(
      users: (_, _, _) async => usersPage(_rows(2), total: 28),
    );
    final container = await _pump(tester, repo);

    container.read(adminTabProvider.notifier).select(0);
    container.read(adminTabProvider.notifier).select(1);
    await tester.pumpAndSettle();

    expect(repo.usersCalls, hasLength(1));
  });

  for (final empty in [false, true]) {
    testWidgets(
      'pulling down fetches ${empty ? 'an empty' : 'the'} list again',
      (tester) async {
        var total = empty ? 0 : 28;
        final repo = FakeAdminRepository(
          users: (_, _, _) async =>
              usersPage(_rows(total.clamp(0, 2)), total: total),
        );
        await _pump(tester, repo);

        total = 29;
        await tester.fling(
          find.text(empty ? 'No trainees yet.' : '28 trainees'),
          const Offset(0, 400),
          1000,
        );
        await tester.pumpAndSettle();

        expect(repo.usersCalls, hasLength(2));
        expect(find.text('29 trainees'), findsOneWidget);
      },
    );
  }

  testWidgets('pulling down works after a failed load too', (tester) async {
    var fail = true;
    final repo = FakeAdminRepository(
      users: (_, _, _) async {
        if (fail) throw refused;
        return usersPage(_rows(2), total: 2);
      },
    );
    await _pump(tester, repo);
    final calls = repo.usersCalls.length;

    fail = false;
    await tester.fling(
      find.text('The server said no.'),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repo.usersCalls.length, greaterThan(calls));
    expect(find.text('Trainee 0'), findsOneWidget);
  });

  testWidgets('a filter sent before the tab opens is the first one asked', (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      users: (_, _, _) async => usersPage(_rows(3)),
    );
    final container = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repo),
        adminTodayProvider.overrideWithValue('2026-11-07'),
      ],
    );
    addTearDown(container.dispose);
    container.listen(adminTabProvider, (_, _) {});
    container.read(adminTabProvider.notifier).select(1, usersFilter: 'pro');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: UsersScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.usersCalls, [(q: '', filter: 'pro', page: 1)]);
  });

  testWidgets('scrolling near the end loads the next page', (tester) async {
    final repo = _paged(62);
    await _pump(tester, repo);
    expect(repo.usersCalls.map((c) => c.page), [1]);

    await tester.scrollUntilVisible(
      find.text('Trainee 29'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(repo.usersCalls.map((c) => c.page), [1, 2]);
    await tester.scrollUntilVisible(
      find.text('Trainee 59'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(repo.usersCalls.map((c) => c.page), [1, 2, 3]);

    await tester.scrollUntilVisible(
      find.text('Trainee 61'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    // 62 of 62 shown: nothing more to ask for.
    expect(repo.usersCalls.map((c) => c.page), [1, 2, 3]);
  });

  testWidgets('a spinner row shows while the next page loads', (tester) async {
    final next = Completer<AdminUsersPage>();
    final repo = FakeAdminRepository(
      users: (_, _, page) => page == 1
          ? Future.value(usersPage(_rows(30), total: 40))
          : next.future,
    );
    await _pump(tester, repo);

    await tester.scrollUntilVisible(
      find.text('Trainee 29'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    next.complete(usersPage(_rows(10, from: 30), page: 2, total: 40));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a search with no match offers Clear search', (tester) async {
    final repo = FakeAdminRepository(
      users: (q, _, _) async => usersPage(q.isEmpty ? _rows(3) : const []),
    );
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('admin.users.search')), 'zz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('No trainees match "zz".'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.users.clear')));
    await tester.pumpAndSettle();

    expect(repo.usersCalls.last.q, '');
    expect(find.text('Trainee 0'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('admin.users.search')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('no trainees at all says so', (tester) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('No trainees yet.'), findsOneWidget);
    expect(find.byKey(const Key('admin.users.clear')), findsNothing);
  });

  testWidgets('a failed load offers Try again', (tester) async {
    var fail = true;
    final repo = FakeAdminRepository(
      users: (_, _, _) async {
        if (fail) throw refused;
        return usersPage(_rows(2));
      },
    );
    await _pump(tester, repo);

    expect(find.text('The server said no.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('admin.users.retry')));
    await tester.pumpAndSettle();

    expect(find.text('Trainee 0'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      FakeAdminRepository(
        users: (_, _, _) async => usersPage([
          sampleRow(
            fullName: 'Maria Concepcion Dela Cruz-Santos',
            email: 'maria.concepcion.delacruz@example.com',
            isPro: true,
            suspended: true,
            lastActiveOn: '2026-10-26',
          ),
          ..._rows(5),
        ]),
      ),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(users: (_, _, _) async => usersPage(_rows(3))),
      dark: true,
    );

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('Users'))).brightness,
      Brightness.dark,
    );
  });
}
