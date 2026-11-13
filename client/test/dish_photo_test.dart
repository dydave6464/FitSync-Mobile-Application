import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/dish_photo.dart';

import 'helpers/fake_dish_photos.dart';
import 'helpers/fake_image_http.dart';

const _url = 'http://fitsync.test/storage/foods/a.jpg';

Future<void> _pump(
  WidgetTester tester,
  Widget photo, {
  bool reduceMotion = false,
  double dpr = 1,
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(400 * dpr, 800 * dpr);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: dark ? fsDarkTheme() : fsLightTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(body: Center(child: photo)),
  ));
}

/// Lets the image decode for real (it cannot in fake time), then builds
/// the frame it delivered.
Future<void> _decode(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
}

FsTokens _tokens(WidgetTester tester) => tester.element(find.byType(DishPhoto)).fs;

/// The photo's opacity: 1 when nothing fades it.
double _opacity(WidgetTester tester) {
  final o = find.descendant(of: find.byType(DishPhoto), matching: find.byType(Opacity));
  return o.evaluate().isEmpty ? 1 : tester.widget<Opacity>(o.first).opacity;
}

void main() {
  setUp(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });
  tearDown(() {
    DishPhoto.debugImage = null;
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('no photo: the leaf tile, at the given size, and no image', (tester) async {
    await _pump(tester, const DishPhoto(url: null, width: 56, height: 56));
    final t = _tokens(tester);
    expect(tester.getSize(find.byKey(const Key('dish.leaf'))), const Size(56, 56));
    expect(tester.getSize(find.byType(DishPhoto)), const Size(56, 56));
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byKey(const Key('dish.leaf')), matching: find.byType(ColoredBox)),
    );
    expect(box.color, t.surface2);
    final icon = tester.widget<Icon>(find.byIcon(Icons.eco_outlined));
    expect(icon.color, t.accentText);
    expect(icon.size, closeTo(56 * 0.42, 0.001));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the leaf tile takes the dark theme too', (tester) async {
    await _pump(tester, const DishPhoto(url: null, width: 48, height: 48), dark: true);
    final t = _tokens(tester);
    expect(t.surface2, fsDarkTheme().extension<FsTokens>()!.surface2);
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byKey(const Key('dish.leaf')), matching: find.byType(ColoredBox)),
    );
    expect(box.color, t.surface2);
    expect(tester.widget<Icon>(find.byIcon(Icons.eco_outlined)).color, t.accentText);
  });

  testWidgets('no photo, without the fallback: nothing at all', (tester) async {
    await _pump(tester, const DishPhoto(url: null, width: 354, height: 199, fallback: false));
    expect(tester.getSize(find.byType(DishPhoto)), Size.zero);
    expect(find.byKey(const Key('dish.leaf')), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('loading: a plain surface2 box of exactly the given size', (tester) async {
    DishPhoto.debugImage = (_, _, _) => PendingImage();
    await _pump(tester, const DishPhoto(url: _url, width: 56, height: 56));
    await tester.pump(const Duration(seconds: 1));
    final loading = find.byKey(const Key('dish.loading'));
    expect(tester.getSize(loading), const Size(56, 56));
    final box = tester.widget<ColoredBox>(find.descendant(of: loading, matching: find.byType(ColoredBox)));
    expect(box.color, _tokens(tester).surface2);
    expect(find.byKey(const Key('dish.leaf')), findsNothing, reason: 'no leaf while it loads');
    expect(find.byIcon(Icons.eco_outlined), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'no spinner');
  });

  testWidgets('loaded: the photo covers the box, clipped to its radius, at its exact size', (tester) async {
    DishPhoto.debugImage = (_, _, _) => onePixelPhoto();
    await _pump(tester, const DishPhoto(url: _url, width: 56, height: 56));
    await _decode(tester);
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byKey(const Key('dish.photo')));
    expect(image.fit, BoxFit.cover);
    expect(image.gaplessPlayback, isTrue);
    expect(image.excludeFromSemantics, isTrue);
    final raw = find.descendant(of: find.byKey(const Key('dish.photo')), matching: find.byType(RawImage));
    expect(tester.getSize(raw), const Size(56, 56));
    expect(tester.getSize(find.byType(DishPhoto)), const Size(56, 56));
    final clip = tester.widget<ClipRRect>(find.ancestor(of: raw, matching: find.byType(ClipRRect)).first);
    expect(clip.borderRadius, BorderRadius.circular(FsRadius.sm));
    expect(find.byKey(const Key('dish.loading')), findsNothing);
    expect(find.byKey(const Key('dish.leaf')), findsNothing);
  });

  testWidgets('a wide photo takes the radius it is given', (tester) async {
    DishPhoto.debugImage = (_, _, _) => onePixelPhoto();
    await _pump(tester, const DishPhoto(url: _url, width: 354, height: 199, radius: FsRadius.md, fallback: false));
    await _decode(tester);
    await tester.pumpAndSettle();
    final raw = find.descendant(of: find.byKey(const Key('dish.photo')), matching: find.byType(RawImage));
    expect(tester.getSize(raw), const Size(354, 199));
    final clip = tester.widget<ClipRRect>(find.ancestor(of: raw, matching: find.byType(ClipRRect)).first);
    expect(clip.borderRadius, BorderRadius.circular(FsRadius.md));
  });

  testWidgets('a photo that fails to load: the leaf tile', (tester) async {
    DishPhoto.debugImage = (_, _, _) => brokenPhoto();
    await _pump(tester, const DishPhoto(url: _url, width: 56, height: 56));
    await _decode(tester);
    expect(tester.getSize(find.byKey(const Key('dish.leaf'))), const Size(56, 56));
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
    expect(find.byKey(const Key('dish.loading')), findsNothing);
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('a photo that fails, without the fallback: nothing, and no space kept', (tester) async {
    DishPhoto.debugImage = (_, _, _) => brokenPhoto();
    await _pump(tester, const DishPhoto(url: _url, width: 354, height: 199, radius: FsRadius.md, fallback: false));
    await _decode(tester);
    expect(tester.getSize(find.byType(DishPhoto)), Size.zero);
    expect(find.byKey(const Key('dish.leaf')), findsNothing);
    expect(find.byKey(const Key('dish.loading')), findsNothing);
  });

  testWidgets('a screen reader never meets the photo: the name beside it says the dish', (tester) async {
    final handle = tester.ensureSemantics();
    DishPhoto.debugImage = (url, _, _) => url.endsWith('broken.jpg') ? brokenPhoto() : onePixelPhoto();
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, url) in const <String?>[_url, null, 'http://fitsync.test/broken.jpg'].indexed)
            Semantics(
              key: Key('host.$i'),
              container: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [DishPhoto(url: url, width: 56, height: 56), const Text('Tinolang manok')],
              ),
            ),
        ],
      ),
    );
    await _decode(tester);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget, reason: 'the first has loaded');
    for (var i = 0; i < 3; i++) {
      final node = tester.getSemantics(find.byKey(Key('host.$i')));
      // No image flag, no other label, no child of its own.
      expect(node, matchesSemantics(label: 'Tinolang manok'), reason: 'host $i');
      expect(node.childrenCount, 0, reason: 'host $i');
    }
    // The whole widget, whatever it draws, is out of the semantics tree
    // (spec 1.1), not only the image inside it.
    for (final photo in find.byType(DishPhoto).evaluate()) {
      Widget? root;
      photo.visitChildElements((c) => root = c.widget);
      expect(root, isA<ExcludeSemantics>().having((w) => w.excluding, 'excluding', isTrue));
    }
    handle.dispose();
  });

  testWidgets('the first frame fades in over 150 ms', (tester) async {
    DishPhoto.debugImage = (_, _, _) => onePixelPhoto();
    await _pump(tester, const DishPhoto(url: _url, width: 56, height: 56));
    await _decode(tester);
    expect(find.byType(RawImage), findsOneWidget);
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 75));
    expect(_opacity(tester), allOf(greaterThan(0.2), lessThan(0.8)));
    await tester.pump(const Duration(milliseconds: 65));
    expect(_opacity(tester), lessThan(1));
    await tester.pump(const Duration(milliseconds: 10));
    expect(_opacity(tester), 1);
  });

  testWidgets('with reduced motion the photo shows at once', (tester) async {
    DishPhoto.debugImage = (_, _, _) => onePixelPhoto();
    await _pump(tester, const DishPhoto(url: _url, width: 56, height: 56), reduceMotion: true);
    await _decode(tester);
    expect(find.byType(RawImage), findsOneWidget);
    expect(_opacity(tester), 1);
  });

  testWidgets('a photo already in memory shows at once: it was never a placeholder', (tester) async {
    final png = onePixelPhoto();
    DishPhoto.debugImage = (_, _, _) => png;
    await _pump(tester, const DishPhoto(url: _url, width: 56, height: 56));
    await _decode(tester);
    await tester.pumpAndSettle();
    // The same photo again, as a row scrolled back into view would draw it.
    await _pump(tester, const DishPhoto(key: Key('again'), url: _url, width: 56, height: 56));
    expect(find.byKey(const Key('dish.loading')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    expect(_opacity(tester), 1);
  });

  testWidgets('decoded at its size on screen: size times the pixel ratio, rounded', (tester) async {
    final asked = <(String, int, int)>[];
    DishPhoto.debugImage = (url, w, h) {
      asked.add((url, w, h));
      return PendingImage();
    };
    await _pump(tester, const DishPhoto(url: _url, width: 41, height: 56), dpr: 2.625);
    // 41 x 2.625 = 107.625, 56 x 2.625 = 147.
    expect(asked.last, (_url, 108, 147));
  });

  testWidgets('by default the photo is fetched, decoded to cover its box without squashing', (tester) async {
    debugNetworkImageHttpClientProvider = imageHttpClient;
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
    await _pump(tester, const DishPhoto(url: _url, width: 160, height: 90, fallback: false), dpr: 2);
    final provider = tester.widget<Image>(find.byKey(const Key('dish.photo'))).image;
    expect(provider, isA<ResizeImage>());
    final resize = provider as ResizeImage;
    expect((resize.imageProvider as NetworkImage).url, _url);
    // A square photo in a 16:9 box: fitted into the box's longer side,
    // both ways, so it keeps its shape and still covers the box sharply.
    expect([resize.width, resize.height, resize.policy], [320, 320, ResizeImagePolicy.fit]);
    await _decode(tester);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(RawImage)), const Size(160, 90));
    debugNetworkImageHttpClientProvider = null;
  });
}
