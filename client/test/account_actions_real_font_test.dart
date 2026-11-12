import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/data/google_sign_in_gateway.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/settings/presentation/change_password_screen.dart';
import 'package:fitsync/features/settings/presentation/delete_account_screen.dart';

/// The real faces, not the test harness's: whether "Delete my account" fits
/// its button at 2x on a 320 dp phone depends on Space Grotesk's widths.
/// Kept in its own file so the screens' other tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// Never reached: these tests only draw the screens.
class _NoopRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoopGoogle implements GoogleSignInGateway {
  @override
  Future<GoogleSignInResult> signIn() async => const GoogleSignInCancelled();
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required double width,
  required double scale,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_NoopRepo()),
        googleSignInGatewayProvider.overrideWithValue(_NoopGoogle()),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// True when [label] inside the button keyed [buttonKey] is shown whole:
/// not cut at a line limit, no word wider than its line, and drawn inside
/// the button rather than past its edge.
bool _whole(WidgetTester tester, String buttonKey, String label) {
  final button = find.byKey(Key(buttonKey));
  final text = find.descendant(of: button, matching: find.text(label));
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  if (paragraph.didExceedMaxLines) return false;
  if (paragraph.getMinIntrinsicWidth(double.infinity) >
      paragraph.size.width + 0.5) {
    return false;
  }
  final inside = tester.getRect(button).inflate(0.5);
  final drawn = tester.getRect(text);
  return inside.contains(drawn.topLeft) && inside.contains(drawn.bottomRight);
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 2.0]) {
      final at = '${width.toInt()} dp at ${scale}x';

      testWidgets('"Delete my account" shows whole, $at', (tester) async {
        await _pump(
          tester,
          const DeleteAccountScreen(hasPassword: true),
          width: width,
          scale: scale,
        );
        expect(
          _whole(tester, 'deleteAccount.submit', 'Delete my account'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('"Confirm with Google" shows whole, $at', (tester) async {
        await _pump(
          tester,
          const DeleteAccountScreen(hasPassword: false),
          width: width,
          scale: scale,
        );
        expect(
          _whole(tester, 'deleteAccount.google', 'Confirm with Google'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('"Change password" shows whole, $at', (tester) async {
        await _pump(
          tester,
          const ChangePasswordScreen(),
          width: width,
          scale: scale,
        );
        expect(_whole(tester, 'save', 'Change password'), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
