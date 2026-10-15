import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/exercises/presentation/exercise_thumb.dart';

const _base = 'http://test.local';
const _still = '/storage/exercises/101/thumb.jpg';
const _gif = '/storage/exercises/101/anim.gif';

final _animation = find.byKey(const ValueKey('thumb.animation'));

/// The URL an [Image] in the tile is loading.
String _urlOf(WidgetTester tester, Finder image) =>
    (tester.widget<Image>(image).image as NetworkImage).url;

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: fsLightTheme(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  testWidgets('with animate on, the tile plays the animation from the same base URL', (tester) async {
    await tester.pumpWidget(_host(const ExerciseThumb(
      size: 72,
      baseUrl: _base,
      thumbnailUrl: _still,
      animationUrl: _gif,
      animate: true,
    )));

    expect(_animation, findsOneWidget);
    expect(_urlOf(tester, _animation), '$_base$_gif');
  });

  testWidgets('Reduce Motion shows the still picture instead', (tester) async {
    await tester.pumpWidget(_host(
      const ExerciseThumb(
        size: 72,
        baseUrl: _base,
        thumbnailUrl: _still,
        animationUrl: _gif,
        animate: true,
      ),
      disableAnimations: true,
    ));

    expect(_animation, findsNothing);
    expect(_urlOf(tester, find.byType(Image)), '$_base$_still');
  });

  testWidgets('with animate off, the tile stays still even when an animation exists', (tester) async {
    await tester.pumpWidget(_host(const ExerciseThumb(
      size: 72,
      baseUrl: _base,
      thumbnailUrl: _still,
      animationUrl: _gif,
    )));

    expect(_animation, findsNothing);
    expect(_urlOf(tester, find.byType(Image)), '$_base$_still');
  });

  testWidgets('with no animation, animate on changes nothing', (tester) async {
    await tester.pumpWidget(_host(const ExerciseThumb(
      size: 72,
      baseUrl: _base,
      thumbnailUrl: _still,
      animate: true,
    )));

    expect(_animation, findsNothing);
    expect(_urlOf(tester, find.byType(Image)), '$_base$_still');
  });

  // A GIF that will not load must not leave a blank tile: the test network
  // answers every image with an error, which is exactly that case.
  testWidgets('an animation that fails to load falls back to the still picture', (tester) async {
    await tester.pumpWidget(_host(const ExerciseThumb(
      size: 72,
      baseUrl: _base,
      thumbnailUrl: _still,
      animationUrl: _gif,
      animate: true,
    )));
    await tester.pumpAndSettle();

    final urls = tester.widgetList<Image>(find.byType(Image))
        .map((i) => (i.image as NetworkImage).url)
        .toList();
    expect(urls, contains('$_base$_still'));
  });
}
