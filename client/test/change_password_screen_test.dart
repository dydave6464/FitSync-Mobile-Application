import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/settings/presentation/change_password_screen.dart';

/// Records every change asked for; [onChange] decides how each one ends.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.onChange});

  final Future<void> Function()? onChange;
  final List<({String current, String next})> changes = [];

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changes.add((current: currentPassword, next: newPassword));
    if (onChange != null) await onChange!();
  }

  @override
  Future<void> deleteAccount({String? password, String? idToken}) =>
      throw UnimplementedError();
  @override
  Future<AuthUser> login(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) => throw UnimplementedError();
  @override
  Future<AuthUser> signInWithGoogle(String idToken) =>
      throw UnimplementedError();
  @override
  Future<AuthUser> me() => throw UnimplementedError();
  @override
  Future<void> signOut() => throw UnimplementedError();
  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
  @override
  Future<void> resendVerification({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> verifyEmail({required String email, required String code}) =>
      throw UnimplementedError();
  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) => throw UnimplementedError();
}

/// A launcher under the screen, so a test can see it close and the
/// SnackBar land on what is left.
Future<void> _pump(
  WidgetTester tester,
  _FakeAuthRepository repo, {
  bool dark = false,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

Future<void> _fill(
  WidgetTester tester, {
  String current = 'old secret',
  String next = 'new secret!',
  String? confirm,
}) async {
  await tester.enterText(find.byKey(const Key('password.current')), current);
  await tester.enterText(find.byKey(const Key('password.new')), next);
  await tester.enterText(
    find.byKey(const Key('password.confirm')),
    confirm ?? next,
  );
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('save')));
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key)));

/// Whether [message] is drawn between the field keyed [above] and the one
/// keyed [below]: under the field it is about.
void _expectBetween(
  WidgetTester tester,
  Finder message,
  String above, [
  String? below,
]) {
  final rect = tester.getRect(message);
  expect(
    rect.top,
    greaterThanOrEqualTo(tester.getRect(find.byKey(Key(above))).bottom),
  );
  if (below != null) {
    expect(rect.bottom, lessThan(tester.getRect(find.byKey(Key(below))).top));
  }
}

void main() {
  testWidgets('three labelled password fields, each hidden with a toggle', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _FakeAuthRepository());

    expect(find.text('Change password'), findsWidgets);
    expect(
      tester.widget<FsButton>(find.byKey(const Key('save'))).label,
      'Change password',
      reason: 'the button says what it does, not a bare Save',
    );
    for (final (key, label) in [
      ('password.current', 'Current password'),
      ('password.new', 'New password'),
      ('password.confirm', 'Confirm new password'),
    ]) {
      expect(_field(tester, key).obscureText, isTrue, reason: key);
      expect(find.text(label), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(Key(key))).label,
        contains(label),
        reason: 'the field is announced by its name',
      );
      final toggle = find.byKey(Key('$key.reveal'));
      expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      await tester.tap(toggle);
      await tester.pump();
      expect(_field(tester, key).obscureText, isFalse, reason: key);
    }
    expect(find.text('At least 8 characters'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an empty current password is asked for, nothing is sent', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo);
    await _fill(tester, current: '');
    await _submit(tester);

    final message = find.text('Enter your current password.');
    expect(message, findsOneWidget);
    _expectBetween(tester, message, 'password.current', 'password.new');
    expect(repo.changes, isEmpty);
  });

  testWidgets('a new password under 8 characters is refused before sending', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo);
    await _fill(tester, next: 'short');
    await _submit(tester);

    final message = find.text('Use at least 8 characters.');
    expect(message, findsOneWidget);
    _expectBetween(tester, message, 'password.new', 'password.confirm');
    expect(repo.changes, isEmpty);
  });

  testWidgets('a confirmation that does not match is refused before sending', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo);
    await _fill(tester, confirm: 'new secret?');
    await _submit(tester);

    final message = find.text("The passwords don't match.");
    expect(message, findsOneWidget);
    _expectBetween(tester, message, 'password.confirm');
    expect(repo.changes, isEmpty);
  });

  testWidgets('a field message goes once that field is edited', (tester) async {
    await _pump(tester, _FakeAuthRepository());
    await _fill(tester, next: 'short', confirm: 'short');
    await _submit(tester);
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('password.new')), 'longer one');
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsNothing);
  });

  testWidgets('a change closes the screen and says other devices signed out', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pump(tester, repo);
    await _fill(tester);
    await _submit(tester);

    expect(repo.changes, [(current: 'old secret', next: 'new secret!')]);
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(
      find.text('Password changed. Other devices were signed out.'),
      findsOneWidget,
    );
  });

  testWidgets('a wrong current password is said under that field', (
    tester,
  ) async {
    final repo = _FakeAuthRepository(
      onChange: () async => throw const ApiException(
        'WRONG_PASSWORD',
        "That password isn't right.",
      ),
    );
    await _pump(tester, repo);
    await _fill(tester);
    await _submit(tester);

    final message = find.text("That password isn't right.");
    expect(message, findsOneWidget);
    _expectBetween(tester, message, 'password.current', 'password.new');
    expect(find.byKey(const Key('error')), findsNothing);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(
      _field(tester, 'password.new').controller!.text,
      'new secret!',
      reason: 'one wrong character must not cost the whole form',
    );
  });

  testWidgets('any other failure is a live error line in plain words', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repo = _FakeAuthRepository(
      onChange: () async => throw const ApiException('NETWORK_ERROR', 'raw'),
    );
    await _pump(tester, repo);
    await _fill(tester);
    await _submit(tester);

    final line = find.byKey(const Key('error'));
    expect(line, findsOneWidget);
    expect(
      tester.widget<FsErrorLine>(line).message,
      userMessage(const ApiException('NETWORK_ERROR', 'raw')),
    );
    expect(
      tester.getSemantics(line).getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    handle.dispose();
  });

  testWidgets('back asks before throwing typed passwords away', (tester) async {
    await _pump(tester, _FakeAuthRepository());
    await tester.enterText(find.byKey(const Key('password.current')), 'x');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard.confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordScreen), findsNothing);
  });

  testWidgets('each eye names its own field, so no two read alike', (
    tester,
  ) async {
    await _pump(tester, _FakeAuthRepository());
    String tooltip(String key) => tester
        .widget<IconButton>(
          find.descendant(
            of: find.byKey(Key('$key.reveal')),
            matching: find.byType(IconButton),
          ),
        )
        .tooltip!;

    final tooltips = [
      for (final key in [
        'password.current',
        'password.new',
        'password.confirm',
      ])
        tooltip(key),
    ];
    expect(tooltips, [
      'Show current password',
      'Show new password',
      'Show confirmed password',
    ]);
    expect(tooltips.toSet(), hasLength(3), reason: 'TalkBack tells them apart');
  });

  testWidgets('back during a change still says the password changed', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _FakeAuthRepository(onChange: () => gate.future);
    await _pump(tester, repo);
    await _fill(tester);
    await tester.ensureVisible(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordScreen), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.changes, hasLength(1));
    expect(
      find.byKey(const Key('open')),
      findsOneWidget,
      reason: 'the screen under it stays: nothing else is popped',
    );
    expect(
      find.text('Password changed. Other devices were signed out.'),
      findsOneWidget,
      reason: 'the change landed, so the user is told even after leaving',
    );
  });

  testWidgets('back with nothing typed just closes', (tester) async {
    await _pump(tester, _FakeAuthRepository());
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ChangePasswordScreen), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'fits 320 dp at 2x text with every message up (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
        addTearDown(tester.view.reset);
        final repo = _FakeAuthRepository(
          onChange: () async =>
              throw const ApiException('NETWORK_ERROR', 'raw'),
        );
        await _pump(tester, repo, dark: dark, textScale: 2.0);
        expect(tester.takeException(), isNull);

        await _fill(tester, current: '', next: 'short', confirm: 'other');
        await _submit(tester);
        expect(find.text('Enter your current password.'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _fill(tester);
        await _submit(tester);
        expect(find.byKey(const Key('error')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
