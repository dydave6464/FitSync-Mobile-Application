import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/admin/presentation/admin_shell.dart';
import 'package:fitsync/features/admin/presentation/content_screen.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/admin/presentation/revenue_screen.dart';

import 'helpers/fake_admin_repository.dart';

const _tabs = ['Overview', 'Users', 'Content', 'Revenue'];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool dark = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(FakeAdminRepository()),
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
        home: const AdminShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The tab body on screen: the IndexedStack keeps visited tabs alive
/// offstage, and the bar repeats every tab's name.
Finder _body(String text) =>
    find.descendant(of: find.byType(IndexedStack), matching: find.text(text));

void main() {
  testWidgets('shows the four admin tabs and opens on Overview', (
    tester,
  ) async {
    await _pump(tester);

    for (final (index, label) in _tabs.indexed) {
      expect(
        find.descendant(
          of: find.byKey(Key('nav.$index')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(_body('Overview'), findsOneWidget);
    expect(find.byKey(const Key('nav.fab')), findsNothing);
  });

  testWidgets('selecting each tab shows its body', (tester) async {
    await _pump(tester);

    for (final (index, label) in _tabs.indexed) {
      await tester.tap(find.byKey(Key('nav.$index')));
      await tester.pumpAndSettle();
      expect(_body(label), findsOneWidget, reason: '$label tab');
      for (final other in _tabs.where((t) => t != label)) {
        expect(_body(other), findsNothing, reason: '$other behind $label');
      }
    }
  });

  testWidgets('the Content tab is the Content screen', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('nav.2')));
    await tester.pumpAndSettle();

    expect(find.byType(ContentScreen), findsOneWidget);
  });

  testWidgets('the Revenue tab is the Revenue screen', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('nav.3')));
    await tester.pumpAndSettle();

    expect(find.byType(RevenueScreen), findsOneWidget);
  });

  testWidgets('selectTab switches the tab and carries the Users filter', (
    tester,
  ) async {
    final container = await _pump(tester);

    AdminShell.selectTab(
      tester.element(_body('Overview')),
      1,
      usersFilter: 'pro',
    );
    await tester.pumpAndSettle();

    expect(_body('Users'), findsOneWidget);
    expect(container.read(adminTabProvider).index, 1);
    expect(container.read(adminTabProvider).usersFilter, 'pro');
  });

  testWidgets('back on another tab returns to Overview', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('nav.3')));
    await tester.pumpAndSettle();
    expect(_body('Revenue'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_body('Overview'), findsOneWidget);
  });

  testWidgets('fits a 360x640 phone at 2x text', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
    addTearDown(tester.view.reset);

    await _pump(tester, textScale: 2.0);
    for (var index = 0; index < _tabs.length; index++) {
      await tester.tap(find.byKey(Key('nav.$index')));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme', (tester) async {
    await _pump(tester, dark: true);

    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(_body('Overview'))).brightness,
      Brightness.dark,
    );
  });
}
