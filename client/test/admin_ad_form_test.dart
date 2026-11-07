import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/admin/data/ad_image_picker.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/presentation/ad_form_screen.dart';
import 'package:fitsync/features/admin/presentation/providers.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_picker.dart'
    show PickedPhoto, UnsupportedPhoto;

import 'helpers/fake_admin_repository.dart';

/// A 1 x 1 PNG.
final _png = PickedPhoto(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==',
  ),
  'image/png',
);

/// Hands over [results] in turn: a photo, null (backed out) or an
/// exception to throw.
class _FakePicker implements AdImagePicker {
  _FakePicker([this.results = const []]);

  final List<Object?> results;
  int calls = 0;

  @override
  Future<PickedPhoto?> pick() async {
    final result = results[calls++];
    if (result is Exception) throw result;
    return result as PickedPhoto?;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAdminRepository repo, {
  AdminAd? ad,
  _FakePicker? picker,
  bool dark = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      adImagePickerProvider.overrideWithValue(picker ?? _FakePicker([_png])),
      adminTodayProvider.overrideWithValue('2026-11-07'),
    ],
  );
  addTearDown(container.dispose);
  container.listen(adminAdsProvider, (_, _) {});
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => AdFormScreen(ad: ad)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

Finder _field(String name) => find.byKey(Key('admin.ad.$name'));

/// What is drawn in [name]'s box: the field and the error line under it.
Finder _inBox(String name, Finder finder) => find.descendant(
  of: find.byKey(Key('admin.ad.$name.box')),
  matching: finder,
);

Future<void> _type(WidgetTester tester, String name, String text) async {
  await tester.ensureVisible(_field(name));
  await tester.enterText(_field(name), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Opens [name]'s date picker and chooses [day] of the month it opens on.
Future<void> _pickDay(WidgetTester tester, String name, int day) async {
  await _tap(tester, _field(name));
  await tester.tap(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text('$day'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _fillNew(WidgetTester tester) async {
  await _type(tester, 'title', '  Protein bars, 20% off ');
  await _tap(tester, _field('image.pick'));
  await _type(tester, 'advertiser', 'GymShark PH');
  await _type(tester, 'amount', '1200.50');
  await _pickDay(tester, 'startsOn', 1);
  await _pickDay(tester, 'endsOn', 30);
}

VoidCallback? _save(WidgetTester tester) =>
    tester.widget<FsButton>(find.byKey(const Key('save'))).onPressed;

Future<void> _pressSave(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('save')));
  await tester.tap(find.byKey(const Key('save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the new ad form names every field', (tester) async {
    await _pump(tester, FakeAdminRepository());

    expect(find.text('New ad'), findsOneWidget);
    for (final label in [
      'Title',
      'Link · optional',
      'Advertiser',
      'Amount paid (₱)',
    ]) {
      expect(
        find.byWidgetPredicate((w) => w is FsField && w.label == label),
        findsOneWidget,
        reason: label,
      );
    }
    for (final eyebrow in ['IMAGE', 'START DATE', 'END DATE']) {
      expect(find.text(eyebrow), findsOneWidget, reason: eyebrow);
    }
    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('Pause ad'), findsNothing);
  });

  testWidgets('Save waits for every required answer, saying what is missing', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository());
    expect(_save(tester), isNull);
    expect(find.text('Add a title'), findsOneWidget);

    await _type(tester, 'title', 'Protein bars');
    expect(find.text('Choose an image'), findsOneWidget);
    await _tap(tester, _field('image.pick'));
    expect(find.text('Add the advertiser'), findsOneWidget);
    await _type(tester, 'advertiser', 'GymShark PH');
    expect(find.text('Add the amount paid'), findsOneWidget);
    await _type(tester, 'amount', '0');
    expect(find.text('Choose a start date'), findsOneWidget);
    await _pickDay(tester, 'startsOn', 1);
    expect(find.text('Choose an end date'), findsOneWidget);
    expect(_save(tester), isNull);
    await _pickDay(tester, 'endsOn', 30);

    expect(_save(tester), isNotNull);
  });

  testWidgets('saving a new ad sends every field, then says so', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo);
    await _fillNew(tester);
    final listLoads = repo.adsCalls;

    await _pressSave(tester);

    expect(repo.createAdCalls, hasLength(1));
    final sent = repo.createAdCalls.single;
    expect(sent.title, 'Protein bars, 20% off');
    expect(sent.advertiser, 'GymShark PH');
    expect(sent.amountPhp, 1200.5);
    expect(sent.startsOn, '2026-11-01');
    expect(sent.endsOn, '2026-11-30');
    expect(sent.linkUrl, isNull);
    expect(sent.image, _png.bytes);
    expect(sent.mimeType, 'image/png');
    expect(find.byType(AdFormScreen), findsNothing);
    expect(find.text('Ad saved.'), findsOneWidget);
    expect(repo.adsCalls, greaterThan(listLoads));
  });

  testWidgets('a picked image is previewed, and can be changed', (
    tester,
  ) async {
    final picker = _FakePicker([_png, null]);
    await _pump(tester, FakeAdminRepository(), picker: picker);

    await _tap(tester, _field('image.pick'));
    expect(find.byKey(const Key('admin.ad.image.preview')), findsOneWidget);
    expect(find.text('Change image'), findsOneWidget);

    // Backing out of the gallery keeps the image already chosen.
    await _tap(tester, _field('image.pick'));
    expect(picker.calls, 2);
    expect(find.byKey(const Key('admin.ad.image.preview')), findsOneWidget);
  });

  testWidgets('the preview is square, as trainees see the image', (
    tester,
  ) async {
    await _pump(tester, FakeAdminRepository(), picker: _FakePicker([_png]));

    await _tap(tester, _field('image.pick'));
    final preview = tester.getSize(
      find.byKey(const Key('admin.ad.image.preview')),
    );
    expect(preview.width, preview.height);
    expect(
      find.text('JPEG or PNG, up to 1.5 MB. Shown small and square.'),
      findsOneWidget,
    );
  });

  testWidgets('an image that is not a JPEG or PNG says so under Image', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeAdminRepository(),
      picker: _FakePicker([const UnsupportedPhoto()]),
    );

    await _tap(tester, _field('image.pick'));

    expect(
      _inBox('image', find.text('The image must be a JPEG or PNG.')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.ad.image.preview')), findsNothing);
  });

  testWidgets('an image over 1.5 MB says so under Image', (tester) async {
    final big = PickedPhoto(
      Uint8List(1500001)..setAll(0, const [0xFF, 0xD8, 0xFF]),
      'image/jpeg',
    );
    await _pump(tester, FakeAdminRepository(), picker: _FakePicker([big]));

    await _tap(tester, _field('image.pick'));

    expect(
      _inBox('image', find.text('The image must be at most 1.5 MB.')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.ad.image.preview')), findsNothing);
  });

  testWidgets('a link must be https', (tester) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo);
    await _fillNew(tester);
    const error = 'Use a link that starts with https://';

    // Part of the way to https:// is still being typed: no error yet.
    await _type(tester, 'link', 'http');
    expect(find.text(error), findsNothing);
    expect(_save(tester), isNull);

    await _type(tester, 'link', 'http://shop.example.ph');
    expect(_inBox('link', find.text(error)), findsOneWidget);
    expect(_save(tester), isNull);

    await _type(tester, 'link', 'https://shop.example.ph/promo');
    expect(find.text(error), findsNothing);
    await _pressSave(tester);
    expect(repo.createAdCalls.single.linkUrl, 'https://shop.example.ph/promo');
  });

  testWidgets('the amount is ₱0 to ₱1,000,000', (tester) async {
    await _pump(tester, FakeAdminRepository());
    await _fillNew(tester);
    const error = 'Enter an amount from ₱0 to ₱1,000,000.';

    await _type(tester, 'amount', '1000000.01');
    expect(_inBox('amount', find.text(error)), findsOneWidget);
    expect(_save(tester), isNull);

    await _type(tester, 'amount', '1000000');
    expect(find.text(error), findsNothing);
    expect(_save(tester), isNotNull);
  });

  testWidgets('the end date cannot be before the start date', (tester) async {
    await _pump(tester, FakeAdminRepository());
    await _fillNew(tester);

    await _pickDay(tester, 'startsOn', 30);
    await _pickDay(tester, 'endsOn', 10);

    expect(
      _inBox(
        'endsOn',
        find.text("The end date can't be before the start date."),
      ),
      findsOneWidget,
    );
    expect(_save(tester), isNull);
  });

  testWidgets("the server's refusal of a field shows under that field", (
    tester,
  ) async {
    final repo = FakeAdminRepository(
      createAd: (_) async => throw const ApiException(
        'INVALID_ADMIN_FIELD',
        'advertiser must be 1 to 120 characters.',
        details: [
          {'field': 'advertiser'},
        ],
      ),
    );
    await _pump(tester, repo);
    await _fillNew(tester);

    await _pressSave(tester);

    expect(
      _inBox(
        'advertiser',
        find.text('advertiser must be 1 to 120 characters.'),
      ),
      findsOneWidget,
    );
    expect(find.byType(AdFormScreen), findsOneWidget);

    // Changing the field clears its error.
    await _type(tester, 'advertiser', 'GymShark Philippines');
    expect(find.text('advertiser must be 1 to 120 characters.'), findsNothing);
  });

  testWidgets('INVALID_IMAGE shows under Image', (tester) async {
    final repo = FakeAdminRepository(
      createAd: (_) async => throw const ApiException(
        'INVALID_IMAGE',
        'The image is not the image type it says it is.',
      ),
    );
    await _pump(tester, repo);
    await _fillNew(tester);

    await _pressSave(tester);

    expect(
      _inBox(
        'image',
        find.text('The image is not the image type it says it is.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('any other failure shows above Save', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(createAd: (_) async => throw refused),
    );
    await _fillNew(tester);

    await _pressSave(tester);

    expect(find.text('The server said no.'), findsOneWidget);
    expect(find.byType(AdFormScreen), findsOneWidget);
  });

  testWidgets('the edit form opens with the ad, its image optional', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo, ad: sampleAd());

    expect(find.text('Edit ad'), findsOneWidget);
    expect(find.text('Protein bars, 20% off'), findsOneWidget);
    expect(find.text('https://shop.example.ph/'), findsOneWidget);
    expect(find.text('GymShark PH'), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);
    expect(find.text('1 Nov 2026'), findsOneWidget);
    expect(find.text('30 Nov 2026'), findsOneWidget);
    expect(find.byKey(const Key('admin.ad.image.preview')), findsOneWidget);
    expect(find.text('Change image'), findsOneWidget);

    await _type(tester, 'title', 'Protein bars, 30% off');
    await _type(tester, 'link', '');
    await _pressSave(tester);

    final call = repo.updateAdCalls.single;
    expect(call.id, 5);
    expect(call.input.title, 'Protein bars, 30% off');
    expect(call.input.linkUrl, isNull);
    expect(call.input.amountPhp, 1200);
    expect(call.input.image, isNull);
    expect(find.text('Ad saved.'), findsOneWidget);
  });

  // An ad's amount is ad revenue: Overview (always built, tab 0) and a
  // Revenue month already opened must show the figure just typed.
  for (final editing in [false, true]) {
    testWidgets(
      'saving ${editing ? 'an edited' : 'a new'} ad fetches Overview and '
      'Revenue again',
      (tester) async {
        final repo = FakeAdminRepository();
        final container = await _pump(
          tester,
          repo,
          ad: editing ? sampleAd() : null,
        );
        container.listen(adminOverviewProvider, (_, _) {});
        container.listen(adminRevenueProvider(null), (_, _) {});
        container.listen(adminRevenueProvider('2026-10'), (_, _) {});
        await tester.pumpAndSettle();
        final overviews = repo.overviewCalls;
        final months = repo.revenueCalls.length;

        if (editing) {
          await _type(tester, 'amount', '1500');
        } else {
          await _fillNew(tester);
        }
        await _pressSave(tester);

        expect(find.text('Ad saved.'), findsOneWidget);
        expect(repo.overviewCalls, overviews + 1);
        expect(
          repo.revenueCalls.sublist(months),
          unorderedEquals([null, '2026-10']),
        );
      },
    );
  }

  testWidgets('Pause ad and Resume ad change it at once, and say so', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pump(tester, repo, ad: sampleAd());

    await _tap(tester, find.byKey(const Key('admin.ad.pause')));
    expect(repo.setAdActiveCalls, [(id: 5, active: false)]);
    expect(find.text('Ad paused.'), findsOneWidget);
    expect(find.byKey(const Key('admin.ad.resume')), findsOneWidget);
    // No confirm: nothing is lost, and Resume undoes it.
    expect(find.byType(AlertDialog), findsNothing);

    await _tap(tester, find.byKey(const Key('admin.ad.resume')));
    expect(repo.setAdActiveCalls.last, (id: 5, active: true));
    expect(find.text('Ad resumed.'), findsOneWidget);
    expect(find.byKey(const Key('admin.ad.pause')), findsOneWidget);
  });

  testWidgets('a paused ad opens with Resume ad', (tester) async {
    await _pump(
      tester,
      FakeAdminRepository(),
      ad: sampleAd(active: false, status: 'paused'),
    );

    expect(find.byKey(const Key('admin.ad.resume')), findsOneWidget);
    expect(find.byKey(const Key('admin.ad.pause')), findsNothing);
  });

  testWidgets('back asks before throwing an edit away', (tester) async {
    await _pump(tester, FakeAdminRepository(), ad: sampleAd());

    // Untouched: back just leaves.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AdFormScreen), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _type(tester, 'advertiser', 'Someone else');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard.confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(AdFormScreen), findsNothing);
  });

  testWidgets('a newly picked image counts as an edit', (tester) async {
    await _pump(tester, FakeAdminRepository(), ad: sampleAd());

    await _tap(tester, _field('image.pick'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsOneWidget);
  });

  testWidgets('a screen reader can open each date box', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, FakeAdminRepository());

    for (final (name, label) in [
      ('startsOn', 'Start date'),
      ('endsOn', 'End date'),
    ]) {
      await tester.ensureVisible(_field(name));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(_field(name));
      expect(
        node,
        isSemantics(
          label: label,
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
        reason: name,
      );
      tester.semantics.tap(find.semantics.byLabel(label));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget, reason: name);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    handle.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'fits a 360x640 phone at 2x text (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.devicePixelRatio = 2.0;
        tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
        addTearDown(tester.view.reset);

        await _pump(
          tester,
          FakeAdminRepository(),
          ad: sampleAd(),
          dark: dark,
          textScale: 2.0,
        );
        await _type(tester, 'link', 'http://x');
        await _pickDay(tester, 'endsOn', 1);
        await tester.ensureVisible(find.byKey(const Key('admin.ad.pause')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
