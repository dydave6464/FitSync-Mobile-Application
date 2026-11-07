import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/user_detail_screen.dart';
import 'package:fitsync/features/pro/domain/pro_status.dart';

import 'helpers/fake_admin_repository.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  int userId = 7,
  bool dark = false,
  double textScale = 1.0,
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
        home: UserDetailScreen(userId: userId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

final _suspend = find.byKey(const Key('admin.user.suspend'));
final _reinstate = find.byKey(const Key('admin.user.reinstate'));

FsButton _button(WidgetTester tester, Finder finder) =>
    tester.widget<FsButton>(finder);

void main() {
  testWidgets('shows the account information', (tester) async {
    final until = DateTime.utc(2026, 12, 5, 3);
    final repo = FakeAdminRepository(
      user: (id) async => sampleDetail(
        id: id,
        signInMethods: const ['password', 'google'],
        isPro: true,
        proSource: 'paid',
        proUntil: until,
      ),
    );
    await _pump(tester, repo);

    expect(repo.userCalls, [7]);
    expect(find.text('Juan Dela Cruz'), findsWidgets);
    expect(find.text('juan@example.com'), findsOneWidget);
    expect(find.text('Joined 5 Nov 2026'), findsOneWidget);
    expect(
      find.text('Signs in with: Email and password, Google'),
      findsOneWidget,
    );
    expect(find.text('Email verified: Yes'), findsOneWidget);
    expect(find.text('Active 1 d ago'), findsOneWidget);
    expect(find.text('Pro until ${formatProDate(until)}'), findsOneWidget);
    expect(_suspend, findsOneWidget);
    expect(_reinstate, findsNothing);
  });

  testWidgets('names Google alone, an unverified email, granted Pro', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeAdminRepository(
        user: (id) async => sampleDetail(
          signInMethods: const ['google'],
          emailVerified: false,
          isPro: true,
          proSource: 'granted',
          lastActiveOn: null,
        ),
      ),
    );

    expect(find.text('Signs in with: Google'), findsOneWidget);
    expect(find.text('Email verified: No'), findsOneWidget);
    expect(find.text('Pro (granted)'), findsOneWidget);
    expect(find.text('Not active yet'), findsOneWidget);
  });

  testWidgets('a free trainee with a password reads Free', (tester) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('Signs in with: Email and password'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
  });

  testWidgets('Suspend asks first, with the first name', (tester) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo);
    expect(tester.getSize(_suspend).height, greaterThanOrEqualTo(48));
    expect(_button(tester, _suspend).danger, isTrue);
    expect(_button(tester, _suspend).kind, FsButtonKind.ghost);

    await tester.tap(_suspend);
    await tester.pumpAndSettle();

    expect(find.text('Suspend Juan?'), findsOneWidget);
    expect(
      find.text(
        "They're signed out on every phone and can't sign in until you "
        'reinstate them. Their data is kept.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.suspend.cancel')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.suspend.cancel')),
        matching: find.text('Keep'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('admin.suspend.cancel')));
    await tester.pumpAndSettle();

    expect(repo.suspendCalls, isEmpty);
    expect(_suspend, findsOneWidget);
  });

  testWidgets('confirming suspends, says so and offers Reinstate', (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      suspend: (id) async =>
          sampleDetail(id: id, suspendedAt: DateTime.utc(2026, 11, 7, 2)),
    );
    final container = await _pump(tester, repo);
    var listBuilds = 0;
    container.listen(adminUsersProvider, (_, next) {
      if (next.isLoading) listBuilds++;
    });

    await tester.tap(_suspend);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.suspend.confirm')));
    await tester.pumpAndSettle();

    expect(repo.suspendCalls, [7]);
    expect(find.text('Account suspended.'), findsOneWidget);
    expect(find.text('Suspended'), findsOneWidget);
    expect(_suspend, findsNothing);
    expect(_reinstate, findsOneWidget);
    expect(_button(tester, _reinstate).kind, FsButtonKind.primary);
    expect(listBuilds, greaterThan(0), reason: 'the list is refreshed');
  });

  testWidgets('Reinstate needs no confirm and says so', (tester) async {
    final repo = FakeAdminRepository(
      user: (id) async =>
          sampleDetail(id: id, suspendedAt: DateTime.utc(2026, 11, 7, 2)),
      reinstate: (id) async => sampleDetail(id: id),
    );
    final container = await _pump(tester, repo);
    var listBuilds = 0;
    container.listen(adminUsersProvider, (_, next) {
      if (next.isLoading) listBuilds++;
    });

    await tester.tap(_reinstate);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.reinstateCalls, [7]);
    expect(find.text('Account reinstated.'), findsOneWidget);
    expect(_suspend, findsOneWidget);
    expect(listBuilds, greaterThan(0), reason: 'the list is refreshed');
  });

  testWidgets('the button is busy while the call runs', (tester) async {
    final pending = Completer<AdminUserDetail>();
    final repo = FakeAdminRepository(reinstate: (_) => pending.future);
    repo.onUser = (id) async =>
        sampleDetail(id: id, suspendedAt: DateTime.utc(2026, 11, 7));
    await _pump(tester, repo);

    await tester.tap(_reinstate);
    await tester.pump();

    expect(_button(tester, _reinstate).busy, isTrue);
    await tester.tap(_reinstate);
    await tester.pump();
    expect(repo.reinstateCalls, hasLength(1));

    pending.complete(sampleDetail());
    await tester.pumpAndSettle();
  });

  testWidgets('a failure shows its message and keeps the page', (tester) async {
    final repo = FakeAdminRepository(
      suspend: (_) async =>
          throw const ApiException('USER_NOT_FOUND', 'No such trainee.'),
    );
    await _pump(tester, repo);

    await tester.tap(_suspend);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.suspend.confirm')));
    await tester.pumpAndSettle();

    expect(find.text('No such trainee.'), findsOneWidget);
    expect(_button(tester, _suspend).busy, isFalse);
    expect(_suspend, findsOneWidget);
  });

  testWidgets('a failed load offers Try again', (tester) async {
    var fail = true;
    final repo = FakeAdminRepository(
      user: (id) async {
        if (fail) throw refused;
        return sampleDetail(id: id);
      },
    );
    await _pump(tester, repo);

    expect(find.text('The server said no.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('admin.user.retry')));
    await tester.pumpAndSettle();

    expect(find.text('juan@example.com'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      FakeAdminRepository(
        user: (id) async => sampleDetail(
          fullName: 'Maria Concepcion Dela Cruz-Santos',
          email: 'maria.concepcion.delacruz@example.com',
          signInMethods: const ['password', 'google'],
          suspendedAt: DateTime.utc(2026, 11, 7),
        ),
      ),
      textScale: 2.0,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(tester, FakeAdminRepository(), dark: true);

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('juan@example.com'))).brightness,
      Brightness.dark,
    );
  });
}
