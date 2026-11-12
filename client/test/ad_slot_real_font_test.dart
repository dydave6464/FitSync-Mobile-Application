import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/ads/data/ad_source.dart';
import 'package:fitsync/features/ads/presentation/ad_slot.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'helpers/fake_ad_source.dart';

/// The real faces, not the test harness's: whether the card stays 48 dp
/// tall with no image depends on Space Grotesk's line heights. Kept in its
/// own file so the slot's other tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

class _FreeProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => const Profile(
    userId: 1,
    email: 'juan@example.com',
    fullName: 'Juan Dela Cruz',
    onboardingCompleted: true,
    isPremium: false,
    notificationsEnabled: true,
    equipment: [],
    injuries: [],
  );
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  testWidgets('a card whose image fails is still a 48 dp target', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(_FreeProfile.new),
          adSourceProvider.overrideWithValue(FakeAdSource(ad: sampleHouseAd)),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: const [AdSlot(placement: 'home')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The test HTTP client answers 400, so only the title row is left.
    final card = find.byType(FsCard);
    expect(find.byKey(const Key('ad.thumb')), findsNothing);
    expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
  });
}
