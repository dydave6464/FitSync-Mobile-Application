import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

/// The real faces, not the test harness's: where the kg/lb switch sits in
/// the stat card's row depends on the number's baseline in JetBrains Mono,
/// and only the real font puts it where a phone does. Kept in its own file
/// so the rest of the kit's tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  // 1.3x is Android's Largest and close to iOS's larger accessibility sizes:
  // the row grows with the number while the switch stays on its baseline,
  // low in the row, and a band centred on the switch no longer covered the
  // row's top.
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('the stat card switch answers across 48 dp at ${scale}x', (
      tester,
    ) async {
      final picked = <WeightUnit>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fsLightTheme(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 180,
                  child: FsStatField(
                    fieldKey: const Key('weightKg'),
                    label: 'Weight',
                    unit: 'lb',
                    controller: controller,
                    unitControl: FsUnitToggle(
                      value: WeightUnit.lb,
                      onChanged: picked.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final kg = tester.getRect(find.byKey(const Key('unit.kg')));
      final answered = <double>[];
      for (var dy = -60.0; dy <= 60; dy += 0.5) {
        final before = picked.length;
        await tester.tapAt(Offset(kg.center.dx, kg.center.dy + dy));
        if (picked.length > before) answered.add(dy);
      }

      expect(answered.last - answered.first, greaterThanOrEqualTo(48));
      // One strip, no holes in it.
      expect(answered.length, (answered.last - answered.first) / 0.5 + 1);
    });
  }
}
