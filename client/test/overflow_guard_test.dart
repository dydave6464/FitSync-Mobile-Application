import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

/// A replacement for the guard recommendation this branch was originally
/// given: one Fs* widget dropped into a 200dp box at 2.0x scale. That,
/// implemented literally, returns clean for all eleven widgets in the kit —
/// including FsEyebrow and FsTag, which carry no overflow guard at all —
/// because a bare box is not what broke any of the other four. Every
/// overflow this kit has actually shipped was a *context* defect:
///
///  - FsChip overflowed inside a [Wrap]: Wrap bounds each child's own max
///    width up front, but that bound does not, by itself, reach into a
///    child's own internal Row (FsChip renders an icon-slot + label Row).
///  - FsNav overflowed inside the fixed-height Column-shaped bottom bar.
///  - FsButton overflowed for the same underlying reason as FsNav, inside
///    its own internal Row (icon + label): a Flex hands its own non-flex
///    children unbounded main-axis space, regardless of whether the Flex
///    itself is bounded.
///
/// FsEyebrow (bare Text) and FsTag (Container + bare Text) were never
/// exercised by any of those three fixes and carry no guard of their own —
/// both are safe today only because of what their call sites happen to
/// pass them.
///
/// Separately: every existing overflow guard on this branch asserts
/// `tester.takeException()` is null, which only observes a *thrown*
/// RenderFlex assertion. A [Container] positioned by `alignment` (as
/// PlanCard's cover band and Greeting's avatar both are — see
/// home_widgets_test.dart for those two, fixed elsewhere in this branch)
/// gives its child a *loose* constraint instead of a Flex's
/// unbounded-but-checked one: the child can silently ask for more room than
/// it has, report a layout size that satisfies the constraint anyway, and
/// paint the excess past its own box with no exception. That reported size
/// is not lying about a comparison it was asked to make — it is simply not
/// answering the question "does the content actually fit" at all.
/// `RenderBox.getMaxIntrinsicHeight`/`getMaxIntrinsicWidth` answer that
/// question directly: they report what the content needs on its own terms,
/// independent of whatever it was squeezed into. That is what the
/// fixed-size-Container group below checks, alongside takeException.
///
/// This file is organized by hostile context, then by widget, so each
/// group states plainly which widgets are expected to survive it and which
/// are not, rather than a single pass/fail per widget across an implied
/// "must handle everything" bar no widget in this kit actually meets.

const _hostileScale = TextScaler.linear(2.0);
const _longLabel =
    'Adjustable resistance training equipment and accessories catalogue';

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: _hostileScale,
        ),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('unflexed child of a Row (no external Flexible/Expanded)', () {
    // A Flex hands a non-flex child unbounded main-axis space to report its
    // own natural size in, no matter how bounded the Flex's own incoming
    // constraint is. That is true of every widget below equally: none of
    // them can defend against being a bare Row child on their own, and
    // none of the three "fixed" widgets' actual fixes touch this case —
    // FsButton and FsChip's Flexible wraps their *own* internal Row, not
    // themselves, so a large enough label still makes the *whole widget*
    // report a large natural size upward. The only real fix is external:
    // wrap the widget in Flexible/Expanded at the call site, which is
    // exactly what every real call site of FsEyebrow and FsTag already
    // does (level_step.dart wraps FsEyebrow directly; FsTag's sibling in
    // the same Row is the one wrapped, and FsTag's own content is short by
    // construction). These are documented here — expected to throw — so a
    // future attempt to "fix" this by giving FsEyebrow an internal
    // Flexible (which breaks its Center-wrapped use in
    // onboarding_scaffold.dart — Flexible with no Flex ancestor throws
    // "Incorrect use of ParentDataWidget", a hard crash worse than the
    // overflow it would replace) would itself flip one of these tests.
    for (final entry in <String, Widget Function()>{
      'FsButton': () => FsButton(label: _longLabel, onPressed: () {}),
      'FsChip': () => FsChip(label: _longLabel, selected: true, onTap: () {}),
      'FsEyebrow': () => FsEyebrow(_longLabel),
      'FsTag': () => FsTag(_longLabel),
    }.entries) {
      testWidgets('${entry.key} overflows here — known, structural, and '
          'not this widget\'s to fix', (tester) async {
        await tester.pumpWidget(_host(SizedBox(
          width: 320,
          child: Row(children: [entry.value()]),
        )));
        expect(tester.takeException(), isNotNull,
            reason: 'see the group-level comment: no widget here can '
                'defend against being a bare, unwrapped Row child');
      });
    }
  });

  group('unflexed child of a fixed-height Column', () {
    // Same unbounded-main-axis-for-non-flex-children rule as a Row, on a
    // fixed-height box's main axis instead — the context that broke FsNav.
    // Unlike the Row group above, FsNav's real fix and FsEyebrow/FsTag's
    // maxLines fix both work here: none of them need to grow taller than
    // one line, so none of them ask a fixed-height Column for more than it
    // has.
    testWidgets('FsNav', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        height: 58,
        child: FsNav(
          currentIndex: 0,
          onSelect: (_) {},
          items: const [
            FsNavItem(icon: Icons.home_outlined, label: 'Home'),
            FsNavItem(
              icon: Icons.fitness_center_outlined,
              label: 'Adjustable resistance training',
            ),
            FsNavItem(icon: Icons.settings_outlined, label: 'Settings'),
          ],
        ),
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('FsEyebrow', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        height: 40,
        child: Column(children: [FsEyebrow(_longLabel)]),
      )));
      expect(tester.takeException(), isNull,
          reason: 'maxLines: 1 caps this to one line, so it never asks the '
              'fixed-height Column for more than one line\'s worth');
    });

    testWidgets('FsTag', (tester) async {
      // 40, not a tighter figure: FsTag pads 3px top and bottom around its
      // text, and at 2.0x scale a single line of its 10.5px text already
      // needs about 31px including that padding — a height smaller than
      // one guarded line can ever be would not be testing the guard, just
      // an unrealistic fixture.
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        height: 40,
        child: Column(children: [FsTag(_longLabel)]),
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('child of a fixed-size Container (alignment-positioned)', () {
    // The silent-clipping context: no Flex is involved, so nothing here
    // would ever throw regardless of whether a guard exists — a genuine
    // gap would look identical to a fully safe widget under takeException
    // alone. Checked via intrinsic size instead, which is exactly what
    // caught PlanCard's cover band and Greeting's avatar (both fixed
    // elsewhere in this branch; see home_widgets_test.dart) and is
    // reproduced here directly against the kit widgets themselves.
    testWidgets('FsEyebrow', (tester) async {
      await tester.pumpWidget(_host(Container(
        width: 320,
        height: 40,
        alignment: Alignment.bottomLeft,
        child: FsEyebrow(_longLabel),
      )));
      expect(tester.takeException(), isNull);

      final paragraph = tester.renderObject<RenderBox>(
        find.descendant(
            of: find.byType(FsEyebrow), matching: find.byType(RichText)),
      );
      // No padding at this call site, so the full 320px width is available
      // to the text.
      expect(paragraph.getMaxIntrinsicHeight(320), lessThanOrEqualTo(40),
          reason: 'maxLines: 1 must keep this to one line\'s worth of '
              'intrinsic height, not merely report a clamped size while '
              'painting more than that underneath it');
    });

    testWidgets('FsTag', (tester) async {
      // height: 40 for the same reason as the fixed-height-Column case
      // above — smaller than one guarded line's real height would not be
      // testing the guard.
      await tester.pumpWidget(_host(Container(
        width: 100,
        height: 40,
        alignment: Alignment.center,
        child: FsTag(_longLabel),
      )));
      expect(tester.takeException(), isNull);

      final paragraph = tester.renderObject<RenderBox>(
        find.descendant(of: find.byType(FsTag), matching: find.byType(RichText)),
      );
      // FsTag pads 8px each side: 100 - 16 = 84 available for the text.
      expect(paragraph.getMaxIntrinsicHeight(84), lessThanOrEqualTo(40),
          reason: 'maxLines: 1 must keep this to one line\'s worth of '
              'intrinsic height');
    });
  });

  group('child of a Wrap', () {
    // The context that broke FsChip: unlike a Row, Wrap bounds each
    // child's own max width up front (it needs to know whether the child
    // fits the current run), so a Flexible/maxLines-based guard is
    // effective for whichever widget sits directly in it.
    testWidgets('FsChip', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        child: Wrap(children: [
          FsChip(
            label: _longLabel,
            selected: true,
            showCheck: true,
            onTap: () {},
          ),
        ]),
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('FsButton', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        child: Wrap(children: [
          FsButton(label: _longLabel, small: true, onPressed: () {}),
        ]),
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('FsEyebrow', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        child: Wrap(children: [FsEyebrow(_longLabel)]),
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('FsTag', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        child: Wrap(children: [FsTag(_longLabel)]),
      )));
      expect(tester.takeException(), isNull);
    });
  });
}
